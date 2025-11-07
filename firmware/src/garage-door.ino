/*
 * Alexa Garage Door Opener - Particle Argon Firmware
 *
 * Hardware:
 * - Particle Argon
 * - VL53L4CD Time-of-Flight Distance Sensor (I2C)
 * - Adafruit 2.4" TFT FeatherWing (ILI9341)
 * - Relay Module (D7)
 *
 * Cloud Functions:
 * - pressButton: Activates relay for 1 second
 * - getStatus: Returns door status (open/closed/unknown)
 *
 * Cloud Variables:
 * - doorStatus: Current door status string
 * - distance: Current distance reading in mm
 */

#include "Particle.h"
#include "Adafruit_ILI9341.h"
#include "Adafruit_GFX.h"
#include "VL53L4CD_api.h"
#include "VL53L4CD_calibration.h"

// Serial for debugging
SYSTEM_MODE(AUTOMATIC);
SYSTEM_THREAD(ENABLED);

// Pin Definitions
#define RELAY_PIN D7
#define STMPE_CS 6
#define TFT_CS   9
#define TFT_DC   10

// Distance thresholds (in mm)
#define DOOR_CLOSED_THRESHOLD 500    // Less than 500mm = closed
#define DOOR_OPEN_THRESHOLD 2000     // More than 2000mm = open

// Relay timing
#define RELAY_PULSE_DURATION 1000    // 1 second

// Display colors
#define COLOR_BACKGROUND ILI9341_BLACK
#define COLOR_TEXT ILI9341_WHITE
#define COLOR_OPEN ILI9341_GREEN
#define COLOR_CLOSED ILI9341_RED
#define COLOR_UNKNOWN ILI9341_YELLOW
#define COLOR_BUTTON ILI9341_BLUE

// Global objects
Adafruit_ILI9341 tft = Adafruit_ILI9341(TFT_CS, TFT_DC);
VL53L4CD_Dev_t vl53l4cd;

// Global state variables
char doorStatus[20] = "unknown";
uint16_t distance = 0;
unsigned long lastSensorRead = 0;
unsigned long lastDisplayUpdate = 0;
bool relayActive = false;
unsigned long relayStartTime = 0;

// Function prototypes
void setupRelay();
void setupSensor();
void setupDisplay();
int pressButtonHandler(String command);
int getStatusHandler(String command);
void readSensor();
void updateDisplay();
void activateRelay();
void deactivateRelay();
void drawButton(const char* label, uint16_t color, bool pressed = false);
void updateStatusDisplay();

void setup() {
    // Initialize serial for debugging
    Serial.begin(115200);
    delay(2000);
    Serial.println("Garage Door Opener Starting...");

    // Setup hardware
    setupRelay();
    setupDisplay();
    setupSensor();

    // Register cloud functions
    Particle.function("pressButton", pressButtonHandler);
    Particle.function("getStatus", getStatusHandler);

    // Register cloud variables
    Particle.variable("doorStatus", doorStatus);
    Particle.variable("distance", distance);

    Serial.println("Setup complete!");

    // Initial display
    updateDisplay();
}

void loop() {
    // Handle relay timing
    if (relayActive && (millis() - relayStartTime >= RELAY_PULSE_DURATION)) {
        deactivateRelay();
    }

    // Read sensor every 500ms
    if (millis() - lastSensorRead >= 500) {
        readSensor();
        lastSensorRead = millis();
    }

    // Update display every 1000ms
    if (millis() - lastDisplayUpdate >= 1000) {
        updateStatusDisplay();
        lastDisplayUpdate = millis();
    }

    delay(10);
}

void setupRelay() {
    pinMode(RELAY_PIN, OUTPUT);
    digitalWrite(RELAY_PIN, LOW);
    Serial.println("Relay initialized on D7");
}

void setupSensor() {
    Serial.println("Initializing VL53L4CD sensor...");

    // Initialize I2C
    Wire.begin();

    // Initialize sensor structure
    vl53l4cd.I2cDevAddr = 0x29;
    vl53l4cd.I2cHandle = &Wire;

    // Sensor initialization
    uint8_t status;
    uint8_t sensorState = 0;

    status = VL53L4CD_SensorInit(&vl53l4cd);
    if (status) {
        Serial.printlnf("VL53L4CD init failed: %d", status);
        return;
    }

    // Start ranging
    status = VL53L4CD_StartRanging(&vl53l4cd);
    if (status) {
        Serial.printlnf("VL53L4CD start ranging failed: %d", status);
        return;
    }

    Serial.println("VL53L4CD sensor initialized successfully");
}

void setupDisplay() {
    Serial.println("Initializing TFT display...");

    tft.begin();
    tft.setRotation(1); // Landscape mode
    tft.fillScreen(COLOR_BACKGROUND);

    // Draw title
    tft.setTextColor(COLOR_TEXT);
    tft.setTextSize(3);
    tft.setCursor(40, 10);
    tft.println("Garage Door");

    Serial.println("TFT display initialized");
}

void readSensor() {
    uint8_t dataReady = 0;
    VL53L4CD_Result_t results;

    // Check if data is ready
    VL53L4CD_CheckForDataReady(&vl53l4cd, &dataReady);

    if (dataReady) {
        // Get measurement
        VL53L4CD_GetResult(&vl53l4cd, &results);
        VL53L4CD_ClearInterrupt(&vl53l4cd);

        // Update distance (convert to mm)
        distance = results.distance_mm;

        // Determine door status
        const char* oldStatus = doorStatus;

        if (distance < DOOR_CLOSED_THRESHOLD) {
            strcpy(doorStatus, "closed");
        } else if (distance > DOOR_OPEN_THRESHOLD) {
            strcpy(doorStatus, "open");
        } else {
            strcpy(doorStatus, "moving");
        }

        // Publish status change
        if (strcmp(oldStatus, doorStatus) != 0) {
            Particle.publish("door/status", doorStatus, PRIVATE);
            Serial.printlnf("Door status changed: %s (distance: %d mm)", doorStatus, distance);
        }

        // Publish distance periodically
        static unsigned long lastPublish = 0;
        if (millis() - lastPublish >= 10000) {
            Particle.publish("door/distance", String(distance), PRIVATE);
            lastPublish = millis();
        }
    }
}

void updateDisplay() {
    // Clear screen
    tft.fillScreen(COLOR_BACKGROUND);

    // Draw title
    tft.setTextColor(COLOR_TEXT);
    tft.setTextSize(3);
    tft.setCursor(30, 10);
    tft.println("Garage Door");

    // Draw status
    updateStatusDisplay();

    // Draw button
    drawButton("PRESS", COLOR_BUTTON, relayActive);
}

void updateStatusDisplay() {
    // Clear status area
    tft.fillRect(0, 60, 320, 100, COLOR_BACKGROUND);

    // Draw status label
    tft.setTextSize(2);
    tft.setTextColor(COLOR_TEXT);
    tft.setCursor(20, 70);
    tft.println("Status:");

    // Draw status value with appropriate color
    uint16_t statusColor = COLOR_UNKNOWN;
    if (strcmp(doorStatus, "open") == 0) {
        statusColor = COLOR_OPEN;
    } else if (strcmp(doorStatus, "closed") == 0) {
        statusColor = COLOR_CLOSED;
    }

    tft.setTextColor(statusColor);
    tft.setTextSize(3);
    tft.setCursor(20, 100);
    tft.println(doorStatus);

    // Draw distance
    tft.setTextSize(2);
    tft.setTextColor(COLOR_TEXT);
    tft.setCursor(20, 140);
    tft.printf("Distance: %d mm", distance);
}

void drawButton(const char* label, uint16_t color, bool pressed) {
    int x = 90;
    int y = 180;
    int w = 140;
    int h = 50;

    // Draw button background
    if (pressed) {
        tft.fillRect(x, y, w, h, COLOR_OPEN);
    } else {
        tft.fillRect(x, y, w, h, color);
    }

    // Draw button border
    tft.drawRect(x, y, w, h, COLOR_TEXT);
    tft.drawRect(x+1, y+1, w-2, h-2, COLOR_TEXT);

    // Draw button label
    tft.setTextColor(COLOR_TEXT);
    tft.setTextSize(2);

    // Center text
    int textX = x + (w - (strlen(label) * 12)) / 2;
    int textY = y + (h - 16) / 2;

    tft.setCursor(textX, textY);
    tft.println(label);
}

void activateRelay() {
    if (!relayActive) {
        digitalWrite(RELAY_PIN, HIGH);
        relayActive = true;
        relayStartTime = millis();

        Serial.println("Relay activated");
        Particle.publish("relay/activated", "true", PRIVATE);

        // Update display
        drawButton("ACTIVE", COLOR_OPEN, true);
    }
}

void deactivateRelay() {
    if (relayActive) {
        digitalWrite(RELAY_PIN, LOW);
        relayActive = false;

        Serial.println("Relay deactivated");
        Particle.publish("relay/deactivated", "true", PRIVATE);

        // Update display
        drawButton("PRESS", COLOR_BUTTON, false);
    }
}

// Cloud function: Press button (activate relay for 1 second)
int pressButtonHandler(String command) {
    Serial.println("pressButton cloud function called");

    if (!relayActive) {
        activateRelay();
        return 1; // Success
    } else {
        Serial.println("Relay already active, ignoring request");
        return 0; // Already active
    }
}

// Cloud function: Get current status
int getStatusHandler(String command) {
    Serial.printlnf("getStatus called: %s (distance: %d mm)", doorStatus, distance);

    // Return status as integer
    if (strcmp(doorStatus, "closed") == 0) {
        return 0;
    } else if (strcmp(doorStatus, "open") == 0) {
        return 1;
    } else {
        return 2; // Moving or unknown
    }
}
