package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
	"github.com/aws/aws-sdk-go/service/sns"
)

// Particle API configuration
const (
	particleAPIBase = "https://api.particle.io/v1"
)

// Environment variables
var (
	particleAccessToken string
	particleDeviceID    string
	doorStateTable      string
	notificationTopicARN string
	thresholdMinutes    int
	dynamoClient        *dynamodb.DynamoDB
	snsClient           *sns.SNS
)

// DoorState represents the state stored in DynamoDB
type DoorState struct {
	DeviceID          string `json:"deviceId"`
	Status            string `json:"status"`            // "open", "closed", "moving", "unknown"
	LastChecked       int64  `json:"lastChecked"`       // Unix timestamp
	LastOpenedTime    int64  `json:"lastOpenedTime"`    // Unix timestamp when door was last opened
	LastClosedTime    int64  `json:"lastClosedTime"`    // Unix timestamp when door was last closed
	NotificationSent  bool   `json:"notificationSent"`  // Whether notification was sent for current open session
	DurationOpenMins  int64  `json:"durationOpenMins"`  // Minutes door has been open
}

// Particle variable response
type ParticleVariableResponse struct {
	Result string `json:"result"`
	Error  string `json:"error,omitempty"`
}

func init() {
	particleAccessToken = os.Getenv("PARTICLE_ACCESS_TOKEN")
	particleDeviceID = os.Getenv("PARTICLE_DEVICE_ID")
	doorStateTable = os.Getenv("DOOR_STATE_TABLE")
	notificationTopicARN = os.Getenv("NOTIFICATION_TOPIC_ARN")

	thresholdStr := os.Getenv("THRESHOLD_MINUTES")
	if thresholdStr == "" {
		thresholdMinutes = 120 // Default 2 hours
	} else {
		var err error
		thresholdMinutes, err = strconv.Atoi(thresholdStr)
		if err != nil {
			thresholdMinutes = 120
		}
	}

	// Initialize AWS clients
	sess := session.Must(session.NewSession())
	dynamoClient = dynamodb.New(sess)
	snsClient = sns.New(sess)

	fmt.Printf("Monitor initialized - threshold: %d minutes\n", thresholdMinutes)
}

func main() {
	lambda.Start(HandleMonitor)
}

// HandleMonitor is the main Lambda handler for scheduled monitoring
func HandleMonitor(ctx context.Context, event interface{}) error {
	fmt.Println("Door monitor triggered")

	// Get current door status from Particle
	status, err := getDoorStatus()
	if err != nil {
		fmt.Printf("Error getting door status: %v\n", err)
		return err
	}

	fmt.Printf("Current door status: %s\n", status)

	// Get previous state from DynamoDB
	previousState, err := getDoorState()
	if err != nil {
		fmt.Printf("Error getting previous state: %v\n", err)
		// Continue with empty state
		previousState = &DoorState{
			DeviceID: particleDeviceID,
			Status:   "unknown",
		}
	}

	// Update state
	currentTime := time.Now().Unix()
	newState := DoorState{
		DeviceID:         particleDeviceID,
		Status:           status,
		LastChecked:      currentTime,
		LastOpenedTime:   previousState.LastOpenedTime,
		LastClosedTime:   previousState.LastClosedTime,
		NotificationSent: previousState.NotificationSent,
	}

	// Detect state changes
	if status != previousState.Status {
		fmt.Printf("State changed: %s -> %s\n", previousState.Status, status)

		if status == "open" {
			newState.LastOpenedTime = currentTime
			newState.NotificationSent = false
		} else if status == "closed" {
			newState.LastClosedTime = currentTime
			newState.NotificationSent = false
		}
	}

	// Calculate duration if door is open
	if status == "open" && newState.LastOpenedTime > 0 {
		durationSeconds := currentTime - newState.LastOpenedTime
		newState.DurationOpenMins = durationSeconds / 60

		fmt.Printf("Door has been open for %d minutes\n", newState.DurationOpenMins)

		// Check if notification should be sent
		if newState.DurationOpenMins >= int64(thresholdMinutes) && !newState.NotificationSent {
			err := sendNotification(newState.DurationOpenMins)
			if err != nil {
				fmt.Printf("Error sending notification: %v\n", err)
			} else {
				newState.NotificationSent = true
				fmt.Println("Notification sent successfully")
			}
		}
	} else {
		newState.DurationOpenMins = 0
	}

	// Save state to DynamoDB
	err = saveDoorState(&newState)
	if err != nil {
		fmt.Printf("Error saving state: %v\n", err)
		return err
	}

	fmt.Println("Monitor completed successfully")
	return nil
}

// getDoorStatus fetches current door status from Particle device
func getDoorStatus() (string, error) {
	url := fmt.Sprintf("%s/devices/%s/doorStatus?access_token=%s",
		particleAPIBase,
		particleDeviceID,
		particleAccessToken,
	)

	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("error making request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("error reading response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("particle API error (status %d): %s", resp.StatusCode, string(body))
	}

	var result ParticleVariableResponse
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("error unmarshaling response: %w", err)
	}

	if result.Error != "" {
		return "", fmt.Errorf("particle error: %s", result.Error)
	}

	return result.Result, nil
}

// getDoorState retrieves the current state from DynamoDB
func getDoorState() (*DoorState, error) {
	result, err := dynamoClient.GetItem(&dynamodb.GetItemInput{
		TableName: aws.String(doorStateTable),
		Key: map[string]*dynamodb.AttributeValue{
			"deviceId": {
				S: aws.String(particleDeviceID),
			},
		},
	})

	if err != nil {
		return nil, fmt.Errorf("error getting item from DynamoDB: %w", err)
	}

	if result.Item == nil {
		return nil, nil // No existing state
	}

	var state DoorState
	err = dynamodbattribute.UnmarshalMap(result.Item, &state)
	if err != nil {
		return nil, fmt.Errorf("error unmarshaling state: %w", err)
	}

	return &state, nil
}

// saveDoorState saves the current state to DynamoDB
func saveDoorState(state *DoorState) error {
	item, err := dynamodbattribute.MarshalMap(state)
	if err != nil {
		return fmt.Errorf("error marshaling state: %w", err)
	}

	_, err = dynamoClient.PutItem(&dynamodb.PutItemInput{
		TableName: aws.String(doorStateTable),
		Item:      item,
	})

	if err != nil {
		return fmt.Errorf("error putting item to DynamoDB: %w", err)
	}

	return nil
}

// sendNotification sends an SNS notification about the open door
func sendNotification(durationMins int64) error {
	hours := durationMins / 60
	mins := durationMins % 60

	var message string
	if hours > 0 {
		message = fmt.Sprintf(" GARAGE DOOR ALERT\n\nYour garage door has been open for %d hours and %d minutes.\n\nTime: %s",
			hours, mins, time.Now().Format("2006-01-02 15:04:05 MST"))
	} else {
		message = fmt.Sprintf(" GARAGE DOOR ALERT\n\nYour garage door has been open for %d minutes.\n\nTime: %s",
			mins, time.Now().Format("2006-01-02 15:04:05 MST"))
	}

	subject := fmt.Sprintf("Garage Door Open Alert - %d mins", durationMins)

	_, err := snsClient.Publish(&sns.PublishInput{
		TopicArn: aws.String(notificationTopicARN),
		Subject:  aws.String(subject),
		Message:  aws.String(message),
	})

	if err != nil {
		return fmt.Errorf("error publishing to SNS: %w", err)
	}

	return nil
}
