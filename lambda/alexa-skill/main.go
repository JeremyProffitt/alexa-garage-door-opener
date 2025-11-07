package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/dynamodbattribute"
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
	dynamoClient        *dynamodb.DynamoDB
)

// DoorState represents the state stored in DynamoDB
type DoorState struct {
	DeviceID         string `json:"deviceId"`
	Status           string `json:"status"`
	LastChecked      int64  `json:"lastChecked"`
	LastOpenedTime   int64  `json:"lastOpenedTime,omitempty"`
	LastClosedTime   int64  `json:"lastClosedTime,omitempty"`
	LastButtonPress  int64  `json:"lastButtonPress,omitempty"`
	NotificationSent bool   `json:"notificationSent"`
}

// Alexa Request structures
type AlexaRequest struct {
	Version string      `json:"version"`
	Session Session     `json:"session"`
	Request Request     `json:"request"`
	Context interface{} `json:"context"`
}

type Session struct {
	New         bool   `json:"new"`
	SessionID   string `json:"sessionId"`
	Application struct {
		ApplicationID string `json:"applicationId"`
	} `json:"application"`
	User struct {
		UserID string `json:"userId"`
	} `json:"user"`
}

type Request struct {
	Type      string `json:"type"`
	RequestID string `json:"requestId"`
	Timestamp string `json:"timestamp"`
	Locale    string `json:"locale"`
	Intent    Intent `json:"intent,omitempty"`
}

type Intent struct {
	Name  string                 `json:"name"`
	Slots map[string]interface{} `json:"slots,omitempty"`
}

// Alexa Response structures
type AlexaResponse struct {
	Version  string            `json:"version"`
	Response ResponseBody      `json:"response"`
	Session  map[string]string `json:"sessionAttributes,omitempty"`
}

type ResponseBody struct {
	OutputSpeech     OutputSpeech `json:"outputSpeech"`
	Card             *Card        `json:"card,omitempty"`
	ShouldEndSession bool         `json:"shouldEndSession"`
}

type OutputSpeech struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type Card struct {
	Type    string `json:"type"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

// Particle API structures
type ParticleFunctionRequest struct {
	Arg string `json:"arg"`
}

type ParticleFunctionResponse struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	LastApp       string `json:"last_app"`
	Connected     bool   `json:"connected"`
	ReturnValue   int    `json:"return_value"`
	ExecutionTime int    `json:"execution_time"`
}

func init() {
	particleAccessToken = os.Getenv("PARTICLE_ACCESS_TOKEN")
	particleDeviceID = os.Getenv("PARTICLE_DEVICE_ID")
	doorStateTable = os.Getenv("DOOR_STATE_TABLE")

	if particleAccessToken == "" {
		fmt.Println("WARNING: PARTICLE_ACCESS_TOKEN not set")
	}
	if particleDeviceID == "" {
		fmt.Println("WARNING: PARTICLE_DEVICE_ID not set")
	}
	if doorStateTable == "" {
		fmt.Println("WARNING: DOOR_STATE_TABLE not set")
	}

	// Initialize AWS DynamoDB client
	sess := session.Must(session.NewSession())
	dynamoClient = dynamodb.New(sess)
}

func main() {
	lambda.Start(HandleRequest)
}

// HandleRequest is the main Lambda handler
func HandleRequest(ctx context.Context, request AlexaRequest) (AlexaResponse, error) {
	fmt.Printf("Request Type: %s\n", request.Request.Type)

	switch request.Request.Type {
	case "LaunchRequest":
		return handleLaunch(request)
	case "IntentRequest":
		return handleIntent(request)
	case "SessionEndedRequest":
		return handleSessionEnded(request)
	default:
		return buildResponse("I don't understand that request.", true), nil
	}
}

func handleLaunch(request AlexaRequest) (AlexaResponse, error) {
	speech := "Garage door controller ready. Say 'press button' to activate the garage door."
	return buildResponse(speech, false), nil
}

func handleIntent(request AlexaRequest) (AlexaResponse, error) {
	intentName := request.Request.Intent.Name
	fmt.Printf("Intent: %s\n", intentName)

	switch intentName {
	case "PressButtonIntent":
		return handlePressButton()
	case "GetStatusIntent":
		return handleGetStatus()
	case "AMAZON.HelpIntent":
		return handleHelp()
	case "AMAZON.CancelIntent", "AMAZON.StopIntent":
		return handleStop()
	default:
		return buildResponse("I don't understand that command.", true), nil
	}
}

func handleSessionEnded(request AlexaRequest) (AlexaResponse, error) {
	return buildResponse("Goodbye", true), nil
}

func handlePressButton() (AlexaResponse, error) {
	fmt.Println("Pressing garage door button...")

	// Call Particle cloud function
	success, err := callParticleFunction("pressButton", "")
	if err != nil {
		fmt.Printf("Error calling Particle function: %v\n", err)
		speech := "Sorry, I couldn't communicate with the garage door opener. Please try again."
		return buildResponse(speech, true), nil
	}

	if success {
		// Update DynamoDB with button press time
		err = updateButtonPress()
		if err != nil {
			fmt.Printf("Error updating button press in DynamoDB: %v\n", err)
			// Continue anyway - don't fail the request
		}

		speech := "Garage door button pressed. The relay has been activated for one second."
		return buildResponse(speech, true), nil
	}

	speech := "The garage door button is already active. Please wait and try again."
	return buildResponse(speech, true), nil
}

func handleGetStatus() (AlexaResponse, error) {
	fmt.Println("Getting garage door status...")

	// Call Particle cloud function
	status, err := getParticleVariable("doorStatus")
	if err != nil {
		fmt.Printf("Error getting status: %v\n", err)
		speech := "Sorry, I couldn't get the garage door status. Please try again."
		return buildResponse(speech, true), nil
	}

	// Update DynamoDB with current status
	err = updateDoorStatus(status)
	if err != nil {
		fmt.Printf("Error updating status in DynamoDB: %v\n", err)
		// Continue anyway - don't fail the request
	}

	// Get additional info from DynamoDB if door is open
	var additionalInfo string
	if status == "open" {
		state, err := getDoorState()
		if err == nil && state != nil && state.LastOpenedTime > 0 {
			openMins := (time.Now().Unix() - state.LastOpenedTime) / 60
			if openMins > 60 {
				hours := openMins / 60
				mins := openMins % 60
				additionalInfo = fmt.Sprintf(" It has been open for %d hours and %d minutes.", hours, mins)
			} else if openMins > 0 {
				additionalInfo = fmt.Sprintf(" It has been open for %d minutes.", openMins)
			}
		}
	}

	speech := fmt.Sprintf("The garage door is currently %s.%s", status, additionalInfo)
	return buildResponse(speech, true), nil
}

func handleHelp() (AlexaResponse, error) {
	speech := "You can say 'press button' to activate the garage door, or 'get status' to check if the door is open or closed."
	return buildResponse(speech, false), nil
}

func handleStop() (AlexaResponse, error) {
	speech := "Goodbye"
	return buildResponse(speech, true), nil
}

func buildResponse(text string, shouldEnd bool) AlexaResponse {
	return AlexaResponse{
		Version: "1.0",
		Response: ResponseBody{
			OutputSpeech: OutputSpeech{
				Type: "PlainText",
				Text: text,
			},
			ShouldEndSession: shouldEnd,
		},
	}
}

// Particle Cloud API functions
func callParticleFunction(functionName, arg string) (bool, error) {
	url := fmt.Sprintf("%s/devices/%s/%s",
		particleAPIBase,
		particleDeviceID,
		functionName,
	)

	requestBody := ParticleFunctionRequest{Arg: arg}
	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return false, fmt.Errorf("error marshaling request: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return false, fmt.Errorf("error creating request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", particleAccessToken))
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("error making request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("error reading response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("particle API error (status %d): %s", resp.StatusCode, string(body))
	}

	var funcResp ParticleFunctionResponse
	if err := json.Unmarshal(body, &funcResp); err != nil {
		return false, fmt.Errorf("error unmarshaling response: %w", err)
	}

	fmt.Printf("Particle function response: return_value=%d, connected=%v\n",
		funcResp.ReturnValue, funcResp.Connected)

	// Return value of 1 means success, 0 means already active
	return funcResp.ReturnValue == 1, nil
}

func getParticleVariable(variableName string) (string, error) {
	url := fmt.Sprintf("%s/devices/%s/%s?access_token=%s",
		particleAPIBase,
		particleDeviceID,
		variableName,
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

	var result struct {
		Result string `json:"result"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("error unmarshaling response: %w", err)
	}

	return result.Result, nil
}

// DynamoDB helper functions

// getDoorState retrieves the current state from DynamoDB
func getDoorState() (*DoorState, error) {
	if doorStateTable == "" {
		return nil, fmt.Errorf("DOOR_STATE_TABLE not configured")
	}

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

// updateButtonPress updates DynamoDB with the time the button was pressed
func updateButtonPress() error {
	if doorStateTable == "" {
		return nil // Skip if table not configured
	}

	currentTime := time.Now().Unix()

	// Get existing state
	state, err := getDoorState()
	if err != nil {
		fmt.Printf("Error getting existing state: %v\n", err)
		state = &DoorState{
			DeviceID: particleDeviceID,
			Status:   "unknown",
		}
	}

	if state == nil {
		state = &DoorState{
			DeviceID: particleDeviceID,
			Status:   "unknown",
		}
	}

	// Update with button press time
	state.LastButtonPress = currentTime
	state.LastChecked = currentTime

	// Save to DynamoDB
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

	fmt.Println("Button press recorded in DynamoDB")
	return nil
}

// updateDoorStatus updates DynamoDB with the current door status
func updateDoorStatus(status string) error {
	if doorStateTable == "" {
		return nil // Skip if table not configured
	}

	currentTime := time.Now().Unix()

	// Get existing state
	state, err := getDoorState()
	if err != nil {
		fmt.Printf("Error getting existing state: %v\n", err)
		state = &DoorState{
			DeviceID: particleDeviceID,
		}
	}

	if state == nil {
		state = &DoorState{
			DeviceID: particleDeviceID,
		}
	}

	previousStatus := state.Status
	state.Status = status
	state.LastChecked = currentTime

	// Track state changes
	if status != previousStatus {
		fmt.Printf("Status changed: %s -> %s\n", previousStatus, status)

		if status == "open" {
			state.LastOpenedTime = currentTime
			state.NotificationSent = false
		} else if status == "closed" {
			state.LastClosedTime = currentTime
			state.NotificationSent = false
		}
	}

	// Save to DynamoDB
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

	fmt.Printf("Door status updated in DynamoDB: %s\n", status)
	return nil
}
