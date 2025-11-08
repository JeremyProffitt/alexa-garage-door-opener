/*
 * Alexa Garage Door Opener - Particle P2 (Photon2) Firmware
 *
 * Hardware:
 * - Particle P2 (Photon2)
 * - VL53L4CD Time-of-Flight Distance Sensor (I2C at 0x29)
 * - 0.96" OLED Display SSD1306 (I2C at 0x3D, 128x64)
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
#include "Adafruit_SSD1306.h"
#include "Adafruit_GFX.h"
#include "vl53l4cd_class.h"

// Serial for debugging
SYSTEM_MODE(AUTOMATIC);
SYSTEM_THREAD(ENABLED);

// Pin Definitions
#define RELAY_PIN D7
#define VL53L4CD_XSHUT -1  // No XSHUT pin used

// OLED Display Settings
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1  // No reset pin
#define OLED_ADDRESS 0x3D

// Define color constants if not already defined
#ifndef SSD1306_WHITE
#define SSD1306_WHITE 1
#endif
#ifndef SSD1306_BLACK
#define SSD1306_BLACK 0
#endif

// Distance thresholds (in mm)
#define DOOR_CLOSED_THRESHOLD 500    // Less than 500mm = closed
#define DOOR_OPEN_THRESHOLD 2000     // More than 2000mm = open

// Relay timing
#define RELAY_PULSE_DURATION 1000    // 1 second

// Global objects
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
VL53L4CD sensor(&Wire, VL53L4CD_XSHUT);

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
    static unsigned long lastLoopLog = 0;

    // Log loop execution every 10 seconds
    if (millis() - lastLoopLog >= 10000) {
        Serial.printlnf("Loop running - Status: %s, Distance: %d mm, Relay: %s",
                        doorStatus, distance, relayActive ? "ACTIVE" : "INACTIVE");
        lastLoopLog = millis();
    }

    // Handle relay timing
    if (relayActive && (millis() - relayStartTime >= RELAY_PULSE_DURATION)) {
        Serial.println("Relay pulse duration elapsed, deactivating...");
        deactivateRelay();
    }

    // Read sensor every 500ms
    if (millis() - lastSensorRead >= 500) {
        readSensor();
        lastSensorRead = millis();
    }

    // Update display every 1000ms
    if (millis() - lastDisplayUpdate >= 1000) {
        Serial.println("Updating display status...");
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

    // Configure sensor
    sensor.begin();

    // Switch off sensor
    sensor.VL53L4CD_Off();

    // Initialize sensor
    sensor.InitSensor();

    // Set ranging timing - highest accuracy (200ms timing budget, low power mode disabled)
    sensor.VL53L4CD_SetRangeTiming(200, 0);

    // Start ranging
    sensor.VL53L4CD_StartRanging();

    Serial.println("VL53L4CD sensor initialized successfully");
}

void setupDisplay() {
    Serial.println("Initializing 0.96\" OLED display (128x64)...");
    Serial.printlnf("OLED I2C Address: 0x%02X", OLED_ADDRESS);

    // Initialize OLED display
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
        Serial.println("OLED allocation failed!");
        // Continue anyway, display just won't work
        return;
    }

    Serial.println("OLED initialized successfully");

    // Clear the display
    display.clearDisplay();

    // Draw initial screen
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(20, 0);
    display.println("Garage Door");
    display.display();

    Serial.println("Display setup complete");
}

void readSensor() {
    static unsigned long lastSensorLog = 0;
    uint8_t dataReady = 0;
    VL53L4CD_Result_t results;
    uint8_t status;

    // Check if data is ready
    status = sensor.VL53L4CD_CheckForDataReady(&dataReady);

    if ((!status) && dataReady) {
        // Clear interrupt
        sensor.VL53L4CD_ClearInterrupt();

        // Get measurement
        sensor.VL53L4CD_GetResult(&results);

        // Log sensor readings every 5 seconds
        if (millis() - lastSensorLog >= 5000) {
            Serial.printlnf("Sensor reading - Distance: %d mm, Range status: %d",
                            results.distance_mm, results.range_status);
            lastSensorLog = millis();
        }

        // Update distance - only use valid measurements (range_status == 0)
        if (results.range_status == 0) {
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
                Serial.printlnf("Door status changed: %s -> %s (distance: %d mm)",
                                oldStatus, doorStatus, distance);
            }

            // Publish distance periodically
            static unsigned long lastPublish = 0;
            if (millis() - lastPublish >= 10000) {
                Particle.publish("door/distance", String(distance), PRIVATE);
                lastPublish = millis();
            }
        } else {
            Serial.printlnf("Invalid sensor reading - range_status: %d", results.range_status);
        }
    }
}

void updateDisplay() {
    Serial.println("Full display update");

    display.clearDisplay();

    // Title at top (smaller font)
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(20, 0);
    display.println("Garage Door");

    // Draw horizontal line
    display.drawLine(0, 10, SCREEN_WIDTH, 10, SSD1306_WHITE);

    // Draw status
    updateStatusDisplay();

    display.display();
}

void updateStatusDisplay() {
    static unsigned long lastDisplayLog = 0;

    // Log display updates every 5 seconds
    if (millis() - lastDisplayLog >= 5000) {
        Serial.printlnf("updateStatusDisplay() - Status: %s, Distance: %d mm", doorStatus, distance);
        lastDisplayLog = millis();
    }

    // Clear content area (below title line)
    display.fillRect(0, 11, SCREEN_WIDTH, SCREEN_HEIGHT - 11, SSD1306_BLACK);

    // Status label (small)
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 14);
    display.println("Status:");

    // Status value (larger)
    display.setTextSize(2);
    display.setCursor(0, 24);
    display.println(doorStatus);

    // Distance (small)
    display.setTextSize(1);
    display.setCursor(0, 42);
    display.printf("Dist: %d mm", distance);

    // Relay status indicator
    display.setCursor(0, 52);
    if (relayActive) {
        display.println("RELAY: ACTIVE");
    } else {
        display.println("Ready");
    }

    display.display();
}

void activateRelay() {
    if (!relayActive) {
        digitalWrite(RELAY_PIN, HIGH);
        relayActive = true;
        relayStartTime = millis();

        Serial.println("Relay activated");
        Particle.publish("relay/activated", "true", PRIVATE);

        // Update display
        updateStatusDisplay();
    }
}

void deactivateRelay() {
    if (relayActive) {
        digitalWrite(RELAY_PIN, LOW);
        relayActive = false;

        Serial.println("Relay deactivated");
        Particle.publish("relay/deactivated", "true", PRIVATE);

        // Update display
        updateStatusDisplay();
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
