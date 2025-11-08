# Alexa Garage Door Opener

An IoT garage door controller using Particle P2 (Photon2) hardware with Alexa voice control integration.

## Overview

This project enables voice-controlled garage door operation through Amazon Alexa using physical hardware components:
- **Particle P2 (Photon2)** microcontroller
- **VL53L4CD** Time-of-Flight distance sensor (for door position detection)
- **Adafruit 2.4" TFT FeatherWing** touchscreen display (320x240)
- **Relay module** for garage door button control

## Features

- **Voice Control**: "Alexa, press garage door button" triggers the relay for 1 second
- **Status Tracking**: Ask Alexa for door status with duration information
- **Smart Notifications**: Automatic alerts if door open > 2 hours (configurable)
- **Distance Sensing**: VL53L4CD sensor monitors door position (open/closed)
- **Visual Display**: TFT touchscreen shows door status and manual control
- **State Persistence**: DynamoDB tracks door state and history
- **Automated Monitoring**: EventBridge-scheduled Lambda checks status every 15 minutes
- **Cloud Integration**: Particle.io cloud backend for device communication
- **Automated Deployment**: GitHub Actions CI/CD pipeline with AWS SAM

## Architecture

```
┌─────────────────┐
│ Alexa Voice Cmd │
└────────┬────────┘
         ↓
┌────────────────────────┐      ┌──────────────────┐
│ Alexa Skill Lambda (Go)│←────→│ DynamoDB (State) │
└───────┬────────────────┘      └──────────────────┘
        ↓
┌──────────────────┐
│ Particle Cloud   │
│ API              │
└────────┬─────────┘
         ↓
┌──────────────────────┐         ┌────────────────────┐
│ Particle P2 (Photon2)│         │ Monitor Lambda (Go)│
│ - VL53L4CD Sensor    │         │ (Every 15 min)     │
│ - TFT Display        │         └─────────┬──────────┘
│ - Relay Control      │                   ↓
└──────────┬───────────┘         ┌──────────────────┐
           ↓                     │ SNS Notification │
    ┌────────────┐               │ (Email/SMS)      │
    │ Garage Door│               └──────────────────┘
    │ Opener     │
    └────────────┘
```

## Project Structure

```
.
├── firmware/           # Particle P2 (Photon2) C++ firmware
│   ├── src/
│   │   └── garage-door.ino
│   └── project.properties
├── lambda/            # AWS Lambda functions
│   ├── alexa-skill/   # Alexa skill handler (Go)
│   │   ├── main.go
│   │   ├── go.mod
│   │   ├── Makefile
│   │   └── test-event.json
│   ├── monitor/       # Door monitoring Lambda (Go)
│   │   ├── main.go
│   │   ├── go.mod
│   │   └── Makefile
│   ├── template.yaml  # AWS SAM template
│   └── samconfig.toml
├── alexa-skill/       # Alexa skill configuration
│   ├── skill.json
│   └── interactionModel.json
├── .github/
│   └── workflows/
│       └── deploy.yml # GitHub Actions CI/CD
├── scripts/
│   ├── setup-secrets.sh
│   └── setup-alexa-skill.sh
├── docs/              # Documentation
│   ├── hardware-setup.md
│   ├── alexa-skill-setup.md
│   └── alexa-skill-model.json
└── README.md
```

## Hardware Setup

### Components
1. **Particle P2 (Photon2)**: Main microcontroller with WiFi/BLE
2. **VL53L4CD Sensor**: I2C distance sensor (0x29)
3. **Adafruit 2.4" TFT FeatherWing**: ILI9341 320x240 touchscreen
4. **Relay Module**: Connected to D7 for garage door button control

### Wiring
- VL53L4CD: I2C (SDA/SCL pins)
- TFT Display: FeatherWing stacks directly on P2
- Relay: D7 (control), 3.3V (VCC), GND

## Quick Start

### 1. Prerequisites
- Particle account with Particle CLI installed
- AWS account with AWS CLI and SAM CLI installed
- Alexa Developer Console account
- GitHub repository with Actions enabled

### 2. Setup GitHub Secrets
```bash
chmod +x scripts/setup-secrets.sh
./scripts/setup-secrets.sh
```

Required secrets:
- `AWS_CLIENT_ID`: AWS access key ID for SAM deployment
- `AWS_SECRET_KEY`: AWS secret access key
- `PARTICLE_ACCESS_TOKEN`: Particle API access token (optional - firmware deployment will be skipped if not provided)
- `PARTICLE_DEVICE_ID`: Particle device ID for "garage-door-opener" (optional)
- `ALEXA_LWA_TOKEN`: LWA (Login with Amazon) refresh token for automated Alexa skill deployment (optional)

Required variables:
- `ALEXA_SKILL_NAME`: Name of your Alexa skill (e.g., "Garage Door Controller")
- `AWS_REGION`: AWS region (default: us-east-2)

Optional variables:
- `NOTIFICATION_EMAIL`: Email for door open alerts (will receive SNS subscription confirmation)
- `DOOR_OPEN_THRESHOLD_MINUTES`: Minutes before notification (default: 120)
- `ALEXA_SKILL_ID`: Alexa Skill ID for production deployment

### 3. Deploy Infrastructure
Push to main or create a branch prefixed with `claude/` to trigger GitHub Actions:
```bash
git push origin main
```

The workflow will:
1. Build and test the Go Lambda functions (Alexa Skill & Monitor)
2. Deploy AWS resources via SAM (Lambda, DynamoDB, SNS, EventBridge)
3. Deploy Alexa skill (if ALEXA_LWA_TOKEN secret is configured)
4. Compile and flash firmware to Particle P2 (if device is online and credentials are configured)

### 4. Configure Alexa Skill

**Option A: Automated Setup (Recommended)**
```bash
./scripts/setup-alexa-skill.sh
```
This script will automatically configure your Alexa skill with the deployed Lambda ARN.

**Option B: Manual Setup**
1. Go to [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask)
2. Create new skill or update existing
3. Set invocation name (e.g., "garage door")
4. Import interaction model from `alexa-skill/interactionModel.json`
5. Set Lambda endpoint to the deployed function ARN (from SAM output)

See `docs/alexa-skill-setup.md` for detailed manual setup instructions.

## Development

### Testing Firmware Locally
```bash
cd firmware
particle compile p2 src/garage-door.ino
```

### Testing Lambda Locally
```bash
cd lambda/alexa-skill
sam local invoke AlexaSkillFunction -e test-event.json
```

### Manual Deployment
```bash
# Deploy Lambda
cd lambda
sam build
sam deploy --guided

# Flash firmware
cd firmware
particle flash garage-door-opener src/
```

## Usage

### Voice Commands

**Press Button:**
- "Alexa, ask garage door to press the button"
- "Alexa, tell garage door to activate"
- "Alexa, ask garage door to press garage door button"

**Check Status:**
- "Alexa, ask garage door for status"
- "Alexa, ask garage door what's the status"
- "Alexa, ask garage door is the door open"

Response includes duration if door is open:
- "The garage door is currently open. It has been open for 2 hours and 15 minutes."

### Manual Control
- Use the TFT touchscreen to press the virtual button
- View door status (open/closed) based on VL53L4CD sensor readings

### Automatic Notifications

The system automatically monitors door status every 15 minutes and sends notifications if:
- Door has been open longer than threshold (default: 2 hours)
- Notification sent via SNS (email/SMS)
- Only one notification per open session

To configure notifications, set GitHub variable `NOTIFICATION_EMAIL`.

## Particle Functions

The firmware exposes these cloud functions:
- `pressButton`: Triggers relay for 1 second
- `getStatus`: Returns door status (open/closed/moving)

The firmware publishes these events:
- `door/status`: Door state changes
- `door/distance`: Distance readings from sensor

## Troubleshooting

### Firmware won't compile
- Ensure Particle libraries are up to date
- Check that device OS version matches project requirements

### Lambda deployment fails
- Verify AWS credentials are correct and secrets use names: `AWS_CLIENT_ID` and `AWS_SECRET_KEY`
- Check SAM CLI version compatibility
- Ensure IAM permissions for CloudFormation, Lambda, DynamoDB, SNS, SSM, and EventBridge

### Alexa skill doesn't respond
- Verify Lambda function ARN in skill configuration
- Check CloudWatch logs for errors
- Test Lambda function independently

### Particle device offline
- GitHub Actions will continue deployment (won't fail)
- Flash firmware manually when device comes online

## Security Considerations

- Store all credentials as GitHub secrets (never commit)
- Use Particle device claiming for secure device access
- Implement rate limiting in Lambda to prevent abuse
- Consider adding confirmation steps for safety

## License

MIT License - See LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## CI/CD Pipeline

The GitHub Actions workflow automatically:
- Builds and tests Go Lambda functions
- Deploys infrastructure with AWS SAM
- Compiles and flashes Particle firmware (when configured)

## Support

For issues and questions:
- Particle Community: https://community.particle.io/
- AWS SAM: https://docs.aws.amazon.com/serverless-application-model/
- Alexa Skills: https://developer.amazon.com/alexa
