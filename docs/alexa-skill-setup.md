# Alexa Skill Setup Guide

Step-by-step guide to creating and configuring the Alexa skill for garage door control.

## Prerequisites

- Amazon Developer account (free at https://developer.amazon.com)
- Lambda function deployed via GitHub Actions (Lambda ARN needed)
- Alexa-enabled device for testing (Echo, Echo Dot, etc.) or Alexa app

## Step 1: Create Alexa Skill

1. **Go to Alexa Developer Console**
   - Visit: https://developer.amazon.com/alexa/console/ask
   - Sign in with your Amazon Developer account

2. **Create New Skill**
   - Click "Create Skill"
   - Enter skill details:
     - **Skill name**: `Garage Door Controller` (or your preferred name)
     - **Primary locale**: English (US)
     - **Model**: Custom
     - **Hosting method**: Provision your own
     - **Hosting region**: Choose closest to your AWS region
   - Click "Create skill"

3. **Choose Template**
   - Select "Start from Scratch"
   - Click "Continue with template"

## Step 2: Configure Invocation

1. **Set Invocation Name**
   - In left sidebar, click "Invocations" ’ "Skill Invocation Name"
   - Enter: `garage door`
   - This is what users say to invoke the skill: "Alexa, ask garage door..."
   - Click "Save Model"

## Step 3: Add Intents

### Option A: Import JSON (Recommended)

1. Click "JSON Editor" in left sidebar
2. Copy contents of `docs/alexa-skill-model.json` from this repository
3. Paste into editor, replacing all existing content
4. Click "Save Model"
5. Click "Build Model" (top right)
6. Wait for build to complete (~1 minute)

### Option B: Manual Creation

#### Create PressButtonIntent

1. Click "Intents" in left sidebar
2. Click "Add Intent"
3. Enter intent name: `PressButtonIntent`
4. Click "Create custom intent"

5. **Add Sample Utterances**:
   - "press the button"
   - "push the button"
   - "activate the garage door"
   - "press garage door button"
   - "push garage door button"
   - "open the garage"
   - "close the garage"
   - "trigger the door"
   - (Add 5-10 variations)

6. Click "Save Model"

#### Create GetStatusIntent

1. Click "Add Intent"
2. Enter intent name: `GetStatusIntent`
3. Click "Create custom intent"

4. **Add Sample Utterances**:
   - "get status"
   - "what's the status"
   - "is the door open"
   - "is the door closed"
   - "check the door"
   - "door status"
   - "tell me the status"

5. Click "Save Model"

#### Build Model

1. Click "Build Model" (top right)
2. Wait for build to complete

## Step 4: Configure Endpoint

1. **Get Lambda ARN**
   - After GitHub Actions deployment completes
   - Check deployment logs or AWS Console
   - ARN format: `arn:aws:lambda:us-east-1:123456789012:function:garage-door-opener-alexa-skill`

2. **Configure in Alexa Console**
   - Click "Endpoint" in left sidebar
   - Select "AWS Lambda ARN"
   - In "Default Region" field, paste your Lambda ARN
   - Leave other regions empty (unless you have multi-region setup)
   - Click "Save Endpoints"

## Step 5: Account Linking (Optional)

For enhanced security, you can add account linking. For this basic setup, it's not required since we're using Particle device IDs.

Skip this section for now.

## Step 6: Configure Permissions (Optional)

If you want to use location-based features in the future:

1. Click "Permissions" in left sidebar
2. Enable any needed permissions
3. For basic functionality, no permissions are required

## Step 7: Test the Skill

### In Alexa Developer Console

1. **Go to Test Tab**
   - Click "Test" in top menu bar
   - Enable testing: Select "Development" from dropdown

2. **Test with Text Input**
   - Type: `ask garage door to press the button`
   - Or: `open garage door` then `press the button`
   - Review Alexa's response

3. **Test with Voice**
   - Click microphone icon
   - Speak: "Ask garage door to press the button"

4. **Review JSON**
   - Click "JSON Input" to see request
   - Click "JSON Output" to see response
   - Check CloudWatch logs if errors occur

### On Physical Device

1. **Enable Skill on Your Account**
   - Alexa app ’ Skills & Games ’ Your Skills ’ Dev
   - Find your skill and enable it

2. **Test Commands**:
   - "Alexa, ask garage door to press the button"
   - "Alexa, ask garage door what's the status"
   - "Alexa, open garage door" (then) "press the button"

## Step 8: Add Skill Icon (Optional)

1. **Create Icons**
   - Small icon: 108x108 px
   - Large icon: 512x512 px
   - Format: PNG or JPG
   - Suggested: Garage door or house icon

2. **Upload**
   - Click "Distribution" ’ "Skill Preview"
   - Upload small and large icons
   - Click "Save"

## Step 9: Skill Metadata (For Publishing)

If you plan to publish the skill (optional):

1. Click "Distribution" in left sidebar
2. Fill out all required fields:
   - **Public Name**: Garage Door Controller
   - **One Sentence Description**: Control your garage door with voice commands
   - **Detailed Description**: Full description of functionality
   - **Example Phrases**:
     - "Alexa, ask garage door to press the button"
     - "Alexa, ask garage door for status"
     - "Alexa, ask garage door to activate"
   - **Category**: Smart Home
   - **Keywords**: garage, door, opener, smart home
   - **Privacy Policy URL**: (if required)
   - **Terms of Use URL**: (if required)

3. Click "Save and continue"

## Troubleshooting

### Skill Doesn't Respond

1. **Check Lambda Configuration**
   ```bash
   aws lambda get-function --function-name garage-door-opener-alexa-skill
   ```

2. **Verify Alexa Trigger**
   ```bash
   aws lambda get-policy --function-name garage-door-opener-alexa-skill
   ```
   Should show Alexa skill permissions

3. **Check CloudWatch Logs**
   - AWS Console ’ CloudWatch ’ Log Groups
   - Find `/aws/lambda/garage-door-opener-alexa-skill`
   - Review recent logs for errors

### "There was a problem with the requested skill's response"

This usually indicates Lambda error:

1. Check Lambda function logs in CloudWatch
2. Verify environment variables are set:
   - `PARTICLE_ACCESS_TOKEN`
   - `PARTICLE_DEVICE_ID`
3. Test Lambda directly:
   ```bash
   aws lambda invoke --function-name garage-door-opener-alexa-skill \
     --payload file://lambda/alexa-skill/test-event.json \
     response.json
   cat response.json
   ```

### Lambda Not Authorized

If you see permission errors:

1. In Alexa Console, go to Endpoint section
2. Copy the Skill ID (starts with `amzn1.ask.skill.`)
3. Update SAM template with Skill ID:
   ```bash
   sam deploy --parameter-overrides "AlexaSkillId=amzn1.ask.skill.xxxxx"
   ```

### Utterances Not Recognized

1. Rebuild the interaction model
2. Add more sample utterances
3. Check for typos in utterances
4. Try more explicit phrasing

### Particle Device Not Responding

1. Verify device is online:
   ```bash
   curl "https://api.particle.io/v1/devices?access_token=YOUR_TOKEN"
   ```

2. Check device logs in Particle Console

3. Test cloud function directly:
   ```bash
   curl -X POST https://api.particle.io/v1/devices/DEVICE_ID/pressButton \
     -d access_token=YOUR_TOKEN
   ```

## Testing Checklist

- [ ] Skill invocation works: "Alexa, open garage door"
- [ ] Press button intent: "Press the button"
- [ ] Get status intent: "What's the status"
- [ ] Help intent: "Help"
- [ ] Stop/Cancel intents: "Stop"
- [ ] Lambda logs show successful execution
- [ ] Particle device receives commands
- [ ] Relay activates for 1 second
- [ ] Distance sensor provides status updates

## Advanced Configuration

### Add Confirmation

For safety, you can add confirmation prompts:

1. In Intent configuration (PressButtonIntent)
2. Enable "Skill Confirmation"
3. Add confirmation prompt: "Are you sure you want to activate the garage door?"
4. Users must say "yes" to confirm

### Rate Limiting

Consider adding rate limiting to prevent rapid repeated commands:

1. Modify Lambda function to track recent invocations
2. Store last activation time in DynamoDB or S3
3. Reject commands within cooldown period (e.g., 5 seconds)

### Multi-Device Support

To control multiple garage doors:

1. Add slots to intents: `{DeviceName}`
2. Update Lambda to route to different Particle devices
3. Store device mappings in DynamoDB
4. Example: "Alexa, ask garage door to open the left door"

### Notifications

Send proactive notifications when door is left open:

1. Enable Alexa Reminders API
2. Add Lambda function to check door status periodically
3. Send notification if door open > threshold time

## Security Best Practices

1. **Limit Access**
   - Only enable skill on trusted Alexa accounts
   - Don't publish skill publicly unless properly secured

2. **Voice PIN** (Advanced)
   - Implement voice PIN for critical commands
   - Require 4-digit code: "Alexa, ask garage door to open, PIN 1234"

3. **Geofencing** (Advanced)
   - Check user's location before allowing activation
   - Require device owner to be near home

4. **Audit Logging**
   - Log all activations to CloudWatch
   - Set up alerts for unusual patterns
   - Review logs regularly

5. **Device Claiming**
   - Ensure Particle device is properly claimed to your account
   - Never share Particle access tokens

## Monitoring

Set up CloudWatch alarms:

```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name garage-door-lambda-errors \
  --alarm-description "Alert on Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1
```

## Skill Publishing (Optional)

If you want others to use your skill:

1. Complete all metadata fields
2. Pass certification requirements:
   - Security review
   - Policy compliance
   - Functional testing
   - Content review

3. Submit for review
4. Wait for Amazon approval (typically 1-2 weeks)

For personal use, keep skill in "Development" stage.

## Example Interactions

Once configured, you can use these commands:

### Basic Usage
- "Alexa, ask garage door to press the button"
- "Alexa, tell garage door to activate"
- "Alexa, ask garage door to push the button"

### With Status Check
- "Alexa, ask garage door what's the status"
- "Alexa, ask garage door if the door is open"
- "Alexa, ask garage door to check the door"

### Natural Flow
```
User: "Alexa, open garage door"
Alexa: "Garage door controller ready. Say press button to activate the garage door."
User: "Press the button"
Alexa: "Garage door button pressed. The relay has been activated for one second."
```

## Next Steps

- Set up CloudWatch dashboards for monitoring
- Configure SNS alerts for errors
- Add more intents (e.g., scheduling, automations)
- Integrate with other smart home devices
- Consider MQTT for real-time status updates

## Resources

- [Alexa Skills Kit Documentation](https://developer.amazon.com/docs/ask-overviews/build-skills-with-the-alexa-skills-kit.html)
- [Custom Skill Tutorial](https://developer.amazon.com/en-US/docs/alexa/custom-skills/steps-to-build-a-custom-skill.html)
- [Lambda with Alexa](https://docs.aws.amazon.com/lambda/latest/dg/services-alexa.html)
- [Voice Design Best Practices](https://developer.amazon.com/en-US/docs/alexa/custom-skills/voice-design-best-practices.html)

## Support

For Alexa-specific issues:
- [Alexa Developer Forums](https://forums.developer.amazon.com/spaces/165/index.html)
- [Stack Overflow - alexa-skills-kit tag](https://stackoverflow.com/questions/tagged/alexa-skills-kit)
