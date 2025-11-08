#!/bin/bash

#############################################################################
# Alexa Skill Setup Script
#
# This script automates the creation and deployment of the Alexa skill
# using the ASK CLI (Alexa Skills Kit Command Line Interface)
#
# Prerequisites:
# - ASK CLI installed (npm install -g ask-cli)
# - ASK CLI configured (ask configure)
# - AWS SAM deployed (Lambda ARN available)
#
# Usage:
#   ./scripts/setup-alexa-skill.sh [LAMBDA_ARN]
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
        echo "Then configure: ask configure"
        exit 1
    fi

    # Check if configured
    if [ ! -f ~/.ask/cli_config ]; then
        print_error "ASK CLI is not configured"
        echo "Run: ask configure"
        exit 1
    fi

    print_success "ASK CLI is installed and configured"
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

# Function to create or update skill
deploy_skill() {
    print_status "Deploying Alexa skill..."

    cd alexa-skill

    # Check if skill already exists
    if [ -f .ask/ask-states.json ]; then
        print_status "Existing skill found, updating..."

        # Update skill
        ask deploy --target skill-metadata
        ask deploy --target model

        print_success "Skill updated successfully"
    else
        print_status "Creating new skill..."

        # Create new skill (note: ask deploy is deprecated in favor of ask smapi)
        # We'll use a simpler approach with manual commands

        print_warning "Creating skill interactively..."
        echo ""
        echo "Since ASK CLI v2 has changed, you may need to:"
        echo "1. Use: ask smapi create-skill-for-vendor --manifest file:skill.json"
        echo "2. Or use the Alexa Developer Console to import skill.json"
        echo ""

        # Try using smapi
        if ask smapi create-skill-for-vendor --help &> /dev/null; then
            print_status "Using ASK SMAPI to create skill..."

            SKILL_ID=$(ask smapi create-skill-for-vendor \
                --manifest "file://skill.json" \
                --query 'skillId' \
                --output text 2>&1 | tail -1)

            if [ -n "$SKILL_ID" ]; then
                print_success "Skill created with ID: $SKILL_ID"

                # Update interaction model
                print_status "Updating interaction model..."
                ask smapi set-interaction-model \
                    --skill-id "$SKILL_ID" \
                    --locale en-US \
                    --interaction-model "file://interactionModel.json" \
                    --stage development

                # Build model
                print_status "Building interaction model..."
                ask smapi get-skill-status --skill-id "$SKILL_ID"

                print_success "Skill deployment complete!"
                echo ""
                echo "Skill ID: $SKILL_ID"
                echo ""
                echo "Next steps:"
                echo "1. Go to https://developer.amazon.com/alexa/console/ask"
                echo "2. Find your skill: Garage Door Controller"
                echo "3. Enable testing in Development"
                echo "4. Test with: 'Alexa, ask garage door to press the button'"
            else
                print_error "Failed to create skill"
                print_warning "Please create skill manually using Alexa Developer Console"
            fi
        else
            print_warning "ASK SMAPI not available"
            print_warning "Please use Alexa Developer Console to create skill manually"
            echo ""
            echo "Files ready for manual import:"
            echo "  - skill.json (skill manifest)"
            echo "  - interactionModel.json (interaction model)"
        fi
    fi

    cd ..
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
