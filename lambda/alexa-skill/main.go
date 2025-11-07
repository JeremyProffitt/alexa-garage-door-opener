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
)

// Particle API configuration
const (
	particleAPIBase = "https://api.particle.io/v1"
)

// Environment variables
var (
	particleAccessToken string
	particleDeviceID    string
)

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

	if particleAccessToken == "" {
		fmt.Println("WARNING: PARTICLE_ACCESS_TOKEN not set")
	}
	if particleDeviceID == "" {
		fmt.Println("WARNING: PARTICLE_DEVICE_ID not set")
	}
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

	speech := fmt.Sprintf("The garage door is currently %s.", status)
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
