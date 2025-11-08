@echo off
REM ###########################################################################
REM GitHub Secrets and Variables Setup Script
REM
REM This script helps configure GitHub repository secrets and variables
REM required for the Alexa Garage Door Opener project.
REM
REM Prerequisites:
REM - GitHub CLI (gh) installed and authenticated
REM - Repository owner/admin access
REM
REM Usage:
REM   scripts\setup-secrets.bat
REM ###########################################################################

setlocal enabledelayedexpansion

REM Colors for output (Windows 10+)
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

REM Function to print colored output
goto :main

:print_status
    echo %BLUE%^=^=^>%NC% %~1
    exit /b

:print_success
    echo %GREEN%✓%NC% %~1
    exit /b

:print_error
    echo %RED%✗%NC% %~1
    exit /b

:print_warning
    echo %YELLOW%⚠%NC% %~1
    exit /b

REM Function to check if gh CLI is installed
:check_gh_cli
    where gh >nul 2>&1
    if %errorlevel% neq 0 (
        call :print_error "GitHub CLI (gh) is not installed"
        echo Install it from: https://cli.github.com/
        exit /b 1
    )

    REM Check if authenticated
    gh auth status >nul 2>&1
    if %errorlevel% neq 0 (
        call :print_error "GitHub CLI is not authenticated"
        echo Run: gh auth login
        exit /b 1
    )

    call :print_success "GitHub CLI is installed and authenticated"
    exit /b 0

REM Function to get repository info
:get_repo_info
    for /f "tokens=*" %%i in ('gh repo view --json nameWithOwner -q .nameWithOwner 2^>nul') do set "REPO=%%i"
    if "!REPO!"=="" (
        call :print_error "Not in a GitHub repository or unable to detect repo"
        exit /b 1
    )
    call :print_success "Repository: !REPO!"
    exit /b 0

REM Function to prompt for secret value
:prompt_secret
    set "secret_name=%~1"
    set "description=%~2"
    set "default_value=%~3"

    echo.
    call :print_status "!description!"

    if not "!default_value!"=="" (
        set /p "secret_value=Enter !secret_name! (or press Enter for default): "
        if "!secret_value!"=="" set "secret_value=!default_value!"
    ) else (
        set /p "secret_value=Enter !secret_name!: "
    )

    exit /b 0

REM Function to prompt for variable value
:prompt_variable
    set "var_name=%~1"
    set "description=%~2"
    set "default_value=%~3"

    echo.
    call :print_status "!description!"

    if not "!default_value!"=="" (
        set /p "var_value=Enter !var_name! (default: !default_value!): "
        if "!var_value!"=="" set "var_value=!default_value!"
    ) else (
        set /p "var_value=Enter !var_name!: "
    )

    exit /b 0

REM Function to set GitHub secret
:set_secret
    set "name=%~1"
    set "value=%~2"

    if "!value!"=="" (
        call :print_warning "Skipping empty secret: !name!"
        exit /b 0
    )

    echo !value!| gh secret set "!name!" --repo="!REPO!"
    call :print_success "Secret set: !name!"
    exit /b 0

REM Function to set GitHub variable
:set_variable
    set "name=%~1"
    set "value=%~2"

    if "!value!"=="" (
        call :print_warning "Skipping empty variable: !name!"
        exit /b 0
    )

    gh variable set "!name!" --body "!value!" --repo="!REPO!"
    call :print_success "Variable set: !name!"
    exit /b 0

REM Main script
:main
    echo.
    echo ╔══════════════════════════════════════════════════════════════════╗
    echo ║   Alexa Garage Door Opener - GitHub Secrets Setup               ║
    echo ╚══════════════════════════════════════════════════════════════════╝
    echo.

    REM Check prerequisites
    call :check_gh_cli
    if %errorlevel% neq 0 exit /b 1

    call :get_repo_info
    if %errorlevel% neq 0 exit /b 1

    echo.
    call :print_status "This script will configure the following secrets and variables:"
    echo   Secrets (encrypted):
    echo     - PARTICLE_ACCESS_TOKEN
    echo     - PARTICLE_DEVICE_ID
    echo     - AWS_CLIENT_ID
    echo     - AWS_SECRET_KEY
    echo.
    echo   Variables (plain text):
    echo     - ALEXA_SKILL_NAME
    echo     - AWS_REGION
    echo.

    set /p "confirm=Continue? (y/n) "
    if /i not "!confirm!"=="y" (
        call :print_warning "Setup cancelled"
        exit /b 0
    )

    REM Collect secrets
    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   SECRETS CONFIGURATION
    echo ════════════════════════════════════════════════════════════════

    call :prompt_secret "PARTICLE_ACCESS_TOKEN" "Particle.io access token (from https://console.particle.io/)" ""
    set "PARTICLE_TOKEN=!secret_value!"

    call :prompt_secret "PARTICLE_DEVICE_ID" "Particle device ID (24-character hex string)" ""
    set "PARTICLE_DEVICE=!secret_value!"

    call :prompt_secret "AWS_CLIENT_ID" "AWS Access Key ID" ""
    set "AWS_KEY=!secret_value!"

    call :prompt_secret "AWS_SECRET_KEY" "AWS Secret Access Key" ""
    set "AWS_SECRET=!secret_value!"

    REM Collect variables
    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   VARIABLES CONFIGURATION
    echo ════════════════════════════════════════════════════════════════

    call :prompt_variable "ALEXA_SKILL_NAME" "Alexa skill name" "Garage Door Controller"
    set "ALEXA_SKILL=!var_value!"

    call :prompt_variable "AWS_REGION" "AWS region" "us-east-1"
    set "AWS_REGION_VAR=!var_value!"

    REM Set secrets
    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   SETTING SECRETS
    echo ════════════════════════════════════════════════════════════════

    call :set_secret "PARTICLE_ACCESS_TOKEN" "!PARTICLE_TOKEN!"
    call :set_secret "PARTICLE_DEVICE_ID" "!PARTICLE_DEVICE!"
    call :set_secret "AWS_CLIENT_ID" "!AWS_KEY!"
    call :set_secret "AWS_SECRET_KEY" "!AWS_SECRET!"

    REM Set variables
    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   SETTING VARIABLES
    echo ════════════════════════════════════════════════════════════════

    call :set_variable "ALEXA_SKILL_NAME" "!ALEXA_SKILL!"
    call :set_variable "AWS_REGION" "!AWS_REGION_VAR!"

    REM Summary
    echo.
    echo ════════════════════════════════════════════════════════════════
    echo   SETUP COMPLETE
    echo ════════════════════════════════════════════════════════════════
    echo.
    call :print_success "All secrets and variables have been configured!"
    echo.
    echo Next steps:
    echo   1. Verify secrets: gh secret list --repo=!REPO!
    echo   2. Verify variables: gh variable list --repo=!REPO!
    echo   3. Push code to trigger deployment
    echo   4. Configure Alexa skill with Lambda ARN from deployment output
    echo.
    call :print_warning "Note: Optional ALEXA_SKILL_ID variable can be set later if needed:"
    echo   gh variable set ALEXA_SKILL_ID --body "amzn1.ask.skill.xxx" --repo=!REPO!
    echo.

endlocal
