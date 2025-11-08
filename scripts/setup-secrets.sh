#!/bin/bash

#############################################################################
# GitHub Secrets and Variables Setup Script
#
# This script helps configure GitHub repository secrets and variables
# required for the Alexa Garage Door Opener project.
#
# Prerequisites:
# - GitHub CLI (gh) installed and authenticated
# - Repository owner/admin access
#
# Usage:
#   ./scripts/setup-secrets.sh
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

# Function to check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated"
        echo "Run: gh auth login"
        exit 1
    fi

    print_success "GitHub CLI is installed and authenticated"
}

# Function to get repository info
get_repo_info() {
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    if [ -z "$REPO" ]; then
        print_error "Not in a GitHub repository or unable to detect repo"
        exit 1
    fi
    print_success "Repository: $REPO"
}

# Function to prompt for secret value
prompt_secret() {
    local secret_name=$1
    local description=$2
    local default_value=$3

    echo ""
    print_status "$description"

    if [ -n "$default_value" ]; then
        read -sp "Enter $secret_name (or press Enter for default): " secret_value
        echo ""
        if [ -z "$secret_value" ]; then
            secret_value=$default_value
        fi
    else
        read -sp "Enter $secret_name: " secret_value
        echo ""
    fi

    echo "$secret_value"
}

# Function to prompt for variable value
prompt_variable() {
    local var_name=$1
    local description=$2
    local default_value=$3

    echo ""
    print_status "$description"

    if [ -n "$default_value" ]; then
        read -p "Enter $var_name (default: $default_value): " var_value
        if [ -z "$var_value" ]; then
            var_value=$default_value
        fi
    else
        read -p "Enter $var_name: " var_value
    fi

    echo "$var_value"
}

# Function to set GitHub secret
set_secret() {
    local name=$1
    local value=$2

    if [ -z "$value" ]; then
        print_warning "Skipping empty secret: $name"
        return
    fi

    echo "$value" | gh secret set "$name" --repo="$REPO"
    print_success "Secret set: $name"
}

# Function to set GitHub variable
set_variable() {
    local name=$1
    local value=$2

    if [ -z "$value" ]; then
        print_warning "Skipping empty variable: $name"
        return
    fi

    gh variable set "$name" --body "$value" --repo="$REPO"
    print_success "Variable set: $name"
}

# Main script
main() {
    echo ""
    echo "TPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPW"
    echo "Q   Alexa Garage Door Opener - GitHub Secrets Setup         Q"
    echo "ZPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP]"
    echo ""

    # Check prerequisites
    check_gh_cli
    get_repo_info

    echo ""
    print_status "This script will configure the following secrets and variables:"
    echo "  Secrets (encrypted):"
    echo "    - PARTICLE_ACCESS_TOKEN"
    echo "    - PARTICLE_DEVICE_ID"
    echo "    - AWS_CLIENT_ID"
    echo "    - AWS_SECRET_KEY"
    echo ""
    echo "  Variables (plain text):"
    echo "    - ALEXA_SKILL_NAME"
    echo "    - AWS_REGION"
    echo ""

    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled"
        exit 0
    fi

    # Collect secrets
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  SECRETS CONFIGURATION"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"

    PARTICLE_TOKEN=$(prompt_secret "PARTICLE_ACCESS_TOKEN" "Particle.io access token (from https://console.particle.io/)")
    PARTICLE_DEVICE=$(prompt_secret "PARTICLE_DEVICE_ID" "Particle device ID (24-character hex string)")
    AWS_KEY=$(prompt_secret "AWS_CLIENT_ID" "AWS Access Key ID")
    AWS_SECRET=$(prompt_secret "AWS_SECRET_KEY" "AWS Secret Access Key")

    # Collect variables
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  VARIABLES CONFIGURATION"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"

    ALEXA_SKILL=$(prompt_variable "ALEXA_SKILL_NAME" "Alexa skill name" "Garage Door Controller")
    AWS_REGION_VAR=$(prompt_variable "AWS_REGION" "AWS region" "us-east-2")

    # Set secrets
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  SETTING SECRETS"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"

    set_secret "PARTICLE_ACCESS_TOKEN" "$PARTICLE_TOKEN"
    set_secret "PARTICLE_DEVICE_ID" "$PARTICLE_DEVICE"
    set_secret "AWS_CLIENT_ID" "$AWS_KEY"
    set_secret "AWS_SECRET_KEY" "$AWS_SECRET"

    # Set variables
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  SETTING VARIABLES"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"

    set_variable "ALEXA_SKILL_NAME" "$ALEXA_SKILL"
    set_variable "AWS_REGION" "$AWS_REGION_VAR"

    # Summary
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  SETUP COMPLETE"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo ""
    print_success "All secrets and variables have been configured!"
    echo ""
    echo "Next steps:"
    echo "  1. Verify secrets: gh secret list --repo=$REPO"
    echo "  2. Verify variables: gh variable list --repo=$REPO"
    echo "  3. Push code to trigger deployment"
    echo "  4. Configure Alexa skill with Lambda ARN from deployment output"
    echo ""
    print_warning "Note: Optional ALEXA_SKILL_ID variable can be set later if needed:"
    echo "  gh variable set ALEXA_SKILL_ID --body \"amzn1.ask.skill.xxx\" --repo=$REPO"
    echo ""
}

# Run main function
main
