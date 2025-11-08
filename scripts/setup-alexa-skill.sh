#!/bin/bash

#############################################################################
# Alexa Skill Setup Script
#
# This script automates the creation and deployment of the Alexa skill
# using the ASK CLI (Alexa Skills Kit Command Line Interface)
#
# Prerequisites:
# - ASK CLI installed (npm install -g ask-cli)
# - ASK CLI configured (ask configure) OR ALEXA_LWA_TOKEN env variable set
# - AWS SAM deployed (Lambda ARN available)
#
# Environment Variables:
#   ALEXA_LWA_TOKEN - LWA (Login with Amazon) refresh token for ASK CLI auth
#
# Usage:
#   ./scripts/setup-alexa-skill.sh [LAMBDA_ARN]
#   ALEXA_LWA_TOKEN=your_token ./scripts/setup-alexa-skill.sh [LAMBDA_ARN]
#############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}${NC} $1"
}

print_error() {
    echo -e "${RED}${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}�${NC} $1"
}

# Function to check if ASK CLI is installed
check_ask_cli() {
    if ! command -v ask &> /dev/null; then
        print_error "ASK CLI is not installed"
        echo "Install it with: npm install -g ask-cli"
        exit 1
    fi

    print_success "ASK CLI is installed"
}

# Function to configure ASK CLI with LWA token
configure_ask_cli() {
    if [ -n "$ALEXA_LWA_TOKEN" ]; then
        print_status "Configuring ASK CLI with LWA token..."

        # Create ASK CLI config directory
        mkdir -p ~/.ask

        # Check if ALEXA_LWA_TOKEN is JSON or plain string
        REFRESH_TOKEN=""
        VENDOR_ID_FROM_JSON=""
        if echo "$ALEXA_LWA_TOKEN" | jq -e . >/dev/null 2>&1; then
            # Token is JSON, extract refresh_token and vendor_id if present
            print_status "Detected JSON format token, extracting refresh_token..."
            REFRESH_TOKEN=$(echo "$ALEXA_LWA_TOKEN" | jq -r '.refresh_token')

            if [ -z "$REFRESH_TOKEN" ] || [ "$REFRESH_TOKEN" = "null" ]; then
                print_error "Failed to extract refresh_token from JSON"
                echo "The ALEXA_LWA_TOKEN appears to be JSON but missing refresh_token field"
                exit 1
            fi

            # Try to extract vendor_id if it exists in the JSON
            VENDOR_ID_FROM_JSON=$(echo "$ALEXA_LWA_TOKEN" | jq -r '.vendor_id // empty')
        else
            # Token is plain string
            REFRESH_TOKEN="$ALEXA_LWA_TOKEN"
        fi

        # Determine vendor ID to use
        VENDOR_ID=""
        if [ -n "$VENDOR_ID_FROM_JSON" ]; then
            VENDOR_ID="$VENDOR_ID_FROM_JSON"
            print_success "Using vendor ID from JSON token: $VENDOR_ID"
        fi

        # Create config with refresh token and vendor_id if available
        if [ -n "$VENDOR_ID" ]; then
            jq -n \
              --arg refresh_token "$REFRESH_TOKEN" \
              --arg vendor_id "$VENDOR_ID" \
              '{
                profiles: {
                  default: {
                    aws_profile: "default",
                    token: {
                      access_token: "",
                      refresh_token: $refresh_token,
                      token_type: "bearer",
                      expires_in: 3600,
                      expires_at: "1970-01-01T00:00:00.000Z"
                    },
                    vendor_id: $vendor_id
                  }
                }
              }' > ~/.ask/cli_config
            print_success "ASK CLI configured with LWA refresh token and vendor ID"
        else
            # Create config without vendor_id, try to fetch it
            jq -n \
              --arg refresh_token "$REFRESH_TOKEN" \
              '{
                profiles: {
                  default: {
                    aws_profile: "default",
                    token: {
                      access_token: "",
                      refresh_token: $refresh_token,
                      token_type: "bearer",
                      expires_in: 3600,
                      expires_at: "1970-01-01T00:00:00.000Z"
                    }
                  }
                }
              }' > ~/.ask/cli_config

            print_status "Attempting to fetch vendor ID from Amazon..."
            # Use smapi command which will refresh the token automatically
            VENDOR_ID_RESPONSE=$(ask smapi list-vendors 2>&1)
            VENDOR_ID=$(echo "$VENDOR_ID_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [ -n "$VENDOR_ID" ]; then
                print_success "Vendor ID retrieved: $VENDOR_ID"
                # Update config with vendor ID
                jq --arg vendor_id "$VENDOR_ID" '.profiles.default.vendor_id = $vendor_id' ~/.ask/cli_config > ~/.ask/cli_config.tmp
                mv ~/.ask/cli_config.tmp ~/.ask/cli_config
                print_success "ASK CLI configured with LWA refresh token and vendor ID"
            else
                print_warning "Could not fetch vendor ID automatically"
                print_status "ASK CLI will attempt to fetch it during deployment"
            fi
        fi
    else
        # Check if manually configured
        if [ ! -f ~/.ask/cli_config ]; then
            print_error "ASK CLI is not configured"
            echo "Either set ALEXA_LWA_TOKEN environment variable or run: ask configure"
            exit 1
        fi

        print_success "Using existing ASK CLI configuration"
    fi
}

# Function to get Lambda ARN
get_lambda_arn() {
    if [ -n "$1" ]; then
        LAMBDA_ARN="$1"
        print_success "Using provided Lambda ARN: $LAMBDA_ARN"
    else
        print_status "Fetching Lambda ARN from AWS CloudFormation..."

        LAMBDA_ARN=$(aws cloudformation describe-stacks \
            --stack-name garage-door-opener \
            --query 'Stacks[0].Outputs[?OutputKey==`AlexaSkillFunctionArn`].OutputValue' \
            --output text 2>/dev/null)

        if [ -z "$LAMBDA_ARN" ]; then
            print_error "Could not fetch Lambda ARN from CloudFormation"
            echo "Please provide Lambda ARN as argument:"
            echo "  ./scripts/setup-alexa-skill.sh arn:aws:lambda:us-east-2:123456789012:function:..."
            exit 1
        fi

        print_success "Lambda ARN: $LAMBDA_ARN"
    fi
}

# Function to update skill.json with Lambda ARN
update_skill_json() {
    print_status "Updating skill.json with Lambda ARN..."

    # Get AWS account ID from Lambda ARN
    ACCOUNT_ID=$(echo "$LAMBDA_ARN" | cut -d':' -f5)

    # Update skill.json
    sed -i.bak "s|ACCOUNT_ID|${ACCOUNT_ID}|g" alexa-skill/skill.json
    sed -i.bak "s|arn:aws:lambda:us-east-2:${ACCOUNT_ID}:function:garage-door-opener-alexa-skill|${LAMBDA_ARN}|g" alexa-skill/skill.json

    print_success "skill.json updated"
}

# Function to setup skill package structure
setup_skill_package() {
    print_status "Setting up skill package structure..."

    cd alexa-skill

    # Create skill package directory structure
    mkdir -p skill-package/interactionModels/custom

    # Copy skill manifest
    cp skill.json skill-package/skill.json

    # Copy interaction model to proper location
    cp interactionModel.json skill-package/interactionModels/custom/en-US.json

    # Create ask-resources.json for ASK CLI v2
    cat > ask-resources.json << EOF
{
  "askcliResourcesVersion": "2020-03-31",
  "profiles": {
    "default": {
      "skillMetadata": {
        "src": "./skill-package"
      }
    }
  }
}
EOF

    print_success "Skill package structure created"
    cd ..
}

# Function to create or update skill
deploy_skill() {
    print_status "Deploying Alexa skill..."

    cd alexa-skill

    # Setup skill package structure
    if [ ! -f ask-resources.json ]; then
        cd ..
        setup_skill_package
        cd alexa-skill
    fi

    # Use ASK CLI v2 deploy command
    print_status "Deploying skill with ASK CLI..."

    # Run ask deploy and capture output
    set +e  # Don't exit on error
    ask deploy > /tmp/ask-deploy.log 2>&1
    DEPLOY_RESULT=$?
    set -e  # Re-enable exit on error

    if [ $DEPLOY_RESULT -eq 0 ]; then
        # Extract skill ID from .ask directory
        if [ -f .ask/ask-states.json ]; then
            SKILL_ID=$(grep -o '"skillId":"[^"]*"' .ask/ask-states.json | cut -d'"' -f4 | head -1)
        fi

        print_success "Skill deployment complete!"
        echo ""
        if [ -n "$SKILL_ID" ]; then
            echo "Skill ID: $SKILL_ID"
            echo ""
        fi
        echo "Next steps:"
        echo "1. Go to https://developer.amazon.com/alexa/console/ask"
        echo "2. Find your skill: Garage Door Controller"
        echo "3. Enable testing in Development"
        echo "4. Test with: 'Alexa, ask garage door to press the button'"

        cd ..
        return 0
    else
        print_error "Skill deployment failed"
        echo ""
        echo "Error log:"
        cat /tmp/ask-deploy.log
        echo ""

        # Check for specific error types
        if grep -q "invalid_grant" /tmp/ask-deploy.log; then
            print_error "Invalid or expired ALEXA_LWA_TOKEN detected"
            echo ""
            echo "The refresh token has been revoked or is invalid."
            echo "To get a new LWA refresh token:"
            echo "  1. Run: ask configure"
            echo "  2. Follow the login prompts"
            echo "  3. Copy the refresh token from ~/.ask/cli_config"
            echo "  4. Update the ALEXA_LWA_TOKEN GitHub secret"
            echo ""
        else
            print_warning "Please check the error above"
            echo ""
            echo "Common issues:"
            echo "  - Invalid or expired ALEXA_LWA_TOKEN"
            echo "  - Skill manifest validation errors"
            echo "  - Network connectivity issues"
            echo ""
        fi

        cd ..
        return 1
    fi
}

# Function to add Lambda trigger permission
add_lambda_permission() {
    print_status "Adding Alexa trigger permission to Lambda..."

    # Extract function name from ARN
    FUNCTION_NAME=$(echo "$LAMBDA_ARN" | cut -d':' -f7)

    # Add permission (will fail if already exists, which is fine)
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id "AlexaSkill" \
        --action "lambda:InvokeFunction" \
        --principal "alexa-appkit.amazon.com" \
        2>&1 | grep -v "ResourceConflictException" || true

    print_success "Lambda permissions configured"
}

# Function to test skill
test_skill() {
    print_status "Testing skill connection..."

    echo ""
    print_warning "Manual testing steps:"
    echo "1. Open Alexa Developer Console: https://developer.amazon.com/alexa/console/ask"
    echo "2. Open 'Garage Door Controller' skill"
    echo "3. Go to 'Test' tab"
    echo "4. Enable testing: Development"
    echo "5. Type or say: 'ask garage door for status'"
    echo ""
}

# Main script
main() {
    echo ""
    echo "TPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPW"
    echo "Q       Alexa Skill Automated Setup Script                  Q"
    echo "ZPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP]"
    echo ""

    # Check prerequisites
    check_ask_cli

    # Configure ASK CLI with LWA token or check existing config
    configure_ask_cli

    # Get Lambda ARN
    get_lambda_arn "$1"

    # Update configuration files
    update_skill_json

    # Deploy skill
    deploy_skill

    # Add Lambda permissions
    add_lambda_permission

    # Show testing instructions
    test_skill

    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  SETUP COMPLETE"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo ""
    print_success "Alexa skill setup finished!"
    echo ""
    echo "Lambda ARN: $LAMBDA_ARN"
    echo ""
    echo "Files created:"
    echo "  - alexa-skill/skill.json (updated with Lambda ARN)"
    echo "  - alexa-skill/interactionModel.json"
    echo ""
    echo "For manual setup, see: docs/alexa-skill-setup.md"
    echo ""
}

# Run main function
main "$@"
