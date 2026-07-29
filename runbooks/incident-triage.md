# Incident Triage Runbook

A repeatable first-response workflow for service-desk and desktop-support incidents.

## 1. Confirm the impact

Record facts before attempting a fix:

| Question | Why it matters |
|---|---|
| Who is affected? | Distinguishes a single-user issue from a wider incident |
| What service or device is affected? | Defines the technical boundary |
| When did it begin? | Helps correlate changes and event logs |
| Can the user work through an alternative? | Determines urgency and workaround options |
| Is sensitive or business-critical data involved? | Triggers the correct security or escalation route |

## 2. Assign an initial priority

Use the organisation's official priority matrix when available.

| Impact | Urgency | Suggested priority | Example |
|---|---|---|---|
| Many users / critical service | High | P1 | Site-wide authentication outage |
| Team or important workflow | High | P2 | Shared application unavailable |
| One user, no workaround | Medium | P3 | Laptop cannot connect to the corporate network |
| One user, workaround available | Low | P4 | Non-critical application preference |

A priority is not based only on who reports the issue. It should reflect business impact and urgency.

## 3. Establish a known-good baseline

1. Confirm the exact error message.
2. Reproduce the problem when safe.
3. Check whether the device has network access.
4. Check date, time and recent restart status.
5. Confirm account state and required permissions.
6. Compare with a known-working user, device or service.
7. Check the service status page and known-issue records.

## 4. Follow the fault domain

### Account or authentication

- confirm username and tenant/domain
- check lockout, expiry and assigned access
- verify system time
- test a web login when permitted
- never ask the user to send a password or MFA code

### Device

- review uptime and pending restart state
- confirm free disk space and memory pressure
- check relevant service status
- review Device Manager or system events
- isolate whether the fault follows the user or the device

### Network

- confirm an active adapter and valid IP configuration
- test the default gateway
- test DNS resolution
- test the required TCP port
- compare Wi-Fi, Ethernet or approved VPN behaviour

### Application

- confirm version and licensing state
- test with a clean profile or safe mode when appropriate
- review logs and dependencies
- check whether the issue is user-specific or system-wide
- repair or reinstall only after recording the current state

## 5. Document every meaningful action

Use the ticket-note template and record:

- observed symptoms
- scope and priority reasoning
- diagnostic evidence
- actions taken
- outcome of each action
- workaround
- user communication
- escalation target and reason

Avoid vague entries such as “fixed issue” or “checked everything.”

## 6. Escalate with evidence

Escalate when:

- the incident exceeds access or support scope
- a security issue is suspected
- a business-critical service is degraded
- a change could create significant risk
- the documented troubleshooting path is exhausted

A useful escalation contains the issue, impact, timeline, evidence, actions already completed, and the precise help required.

## 7. Resolve and close

Before closing:

- confirm the user can complete the original task
- record the final cause when known
- record the solution or workaround
- link a knowledge article when relevant
- note any follow-up action
- use the correct resolution category
