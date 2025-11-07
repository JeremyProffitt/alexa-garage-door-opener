# Alexa Garage Door Opener

An IoT garage door controller using Particle Argon hardware with Alexa voice control integration.

## Overview

This project enables voice-controlled garage door operation through Amazon Alexa using physical hardware components:
- **Particle Argon** microcontroller
- **VL53L4CD** Time-of-Flight distance sensor (for door position detection)
- **Adafruit 2.4" TFT FeatherWing** touchscreen display (320x240)
- **Relay module** for garage door button control

## Features

- **Voice Control**: "Alexa, press garage door button" triggers the relay for 1 second
- **Distance Sensing**: VL53L4CD sensor monitors door position (open/closed)
- **Visual Display**: TFT touchscreen shows door status and manual control
- **Cloud Integration**: Particle.io cloud backend for device communication
- **Automated Deployment**: GitHub Actions CI/CD pipeline with AWS SAM

## Architecture

```
Alexa Voice Command
    ↓
AWS Lambda (Go) ← AWS SAM deployment
    ↓
Particle Cloud API
    ↓
Particle Argon (garage-door-opener)
    ↓
Relay → Garage Door Opener Button
```

## Project Structure

```
.
├── firmware/           # Particle Argon C++ firmware
│   ├── src/
│   │   └── garage-door.ino
│   └── project.properties
├── lambda/            # AWS Lambda functions
│   ├── alexa-skill/   # Alexa skill handler (Go)
│   │   ├── main.go
│   │   └── go.mod
│   └── template.yaml  # AWS SAM template
├── .github/
│   └── workflows/
│       └── deploy.yml # GitHub Actions CI/CD
├── scripts/
│   └── setup-secrets.sh
└── README.md
```

## Hardware Setup

### Components
1. **Particle Argon**: Main microcontroller with WiFi/BLE
2. **VL53L4CD Sensor**: I2C distance sensor (0x29)
3. **Adafruit 2.4" TFT FeatherWing**: ILI9341 320x240 touchscreen
4. **Relay Module**: Connected to D7 for garage door button control

### Wiring
- VL53L4CD: I2C (SDA/SCL pins)
- TFT Display: FeatherWing stacks directly on Argon
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
- `PARTICLE_ACCESS_TOKEN`: Particle API access token
- `AWS_ACCESS_KEY_ID`: AWS credentials for SAM deployment
- `AWS_SECRET_ACCESS_KEY`: AWS secret key
- `PARTICLE_DEVICE_ID`: Device ID for "garage-door-opener"

Required variables:
- `ALEXA_SKILL_NAME`: Name of your Alexa skill (e.g., "Garage Door Controller")
- `AWS_REGION`: AWS region (default: us-east-1)

### 3. Deploy Infrastructure
Push to the designated branch to trigger GitHub Actions:
```bash
git push origin claude/garage-door-opener-project-011CUtSMn2nCqYD7is3G378J
```

The workflow will:
1. Build and test the Go Lambda function
2. Deploy AWS resources via SAM
3. Flash firmware to Particle Argon (if online)

### 4. Configure Alexa Skill
1. Go to [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask)
2. Create new skill or update existing
3. Set invocation name (e.g., "garage door")
4. Add custom intent: "PressButtonIntent" with sample utterances:
   - "press garage door button"
   - "push the button"
   - "activate the garage door"
5. Set Lambda endpoint to the deployed function ARN (from SAM output)

## Development

### Testing Firmware Locally
```bash
cd firmware
particle compile argon src/garage-door.ino
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
- "Alexa, ask garage door to press the button"
- "Alexa, tell garage door to activate"

### Manual Control
- Use the TFT touchscreen to press the virtual button
- View door status (open/closed) based on VL53L4CD sensor readings

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
- Verify AWS credentials are correct
- Check SAM CLI version compatibility
- Ensure IAM permissions for CloudFormation, Lambda, and API Gateway

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

## Support

For issues and questions:
- Particle Community: https://community.particle.io/
- AWS SAM: https://docs.aws.amazon.com/serverless-application-model/
- Alexa Skills: https://developer.amazon.com/alexa
