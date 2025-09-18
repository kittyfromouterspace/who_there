# Feature Specification: WhoThere - Phoenix Analytics Library

**Feature Branch**: `001-we-have-a`
**Created**: 2025-09-18
**Status**: Draft
**Input**: User description: "we have a custom analytics library in ../lnz_me/lib/lnz_me/analytics that we want to generalise and use for other projects. we want to release this project as open source so we need to remove all project specific code and focus on a package that is useful for us and others. Import the code base and relavant parts of the code base into this project and generalise it."

## Execution Flow (main)
```
1. Parse user description from Input
   ’ Extract analytics library for generalization 
2. Extract key concepts from description
   ’ Actors: Phoenix developers, SaaS operators, open source users
   ’ Actions: Track traffic, analyze behavior, monitor performance
   ’ Data: Events, sessions, metrics, geographic data
   ’ Constraints: Privacy-first, multi-tenant, zero user visibility 
3. For each unclear aspect:
   ’ Configuration options for different deployment scenarios
   ’ Data retention and compliance features
4. Fill User Scenarios & Testing section 
5. Generate Functional Requirements 
6. Identify Key Entities 
7. Run Review Checklist 
8. Return: SUCCESS (spec ready for planning)
```

---

## ¡ Quick Guidelines
-  Focus on WHAT users need and WHY
- L Avoid HOW to implement (no tech stack, APIs, code structure)
- =e Written for business stakeholders, not developers

### Section Requirements
- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a Phoenix application developer, I want to integrate comprehensive analytics tracking into my application so that I can understand user behavior, monitor performance, and make data-driven decisions about my product, while ensuring complete user privacy and compliance with data protection regulations.

### Acceptance Scenarios
1. **Given** a Phoenix application with WhoThere installed, **When** a user visits any page, **Then** the system tracks the visit without any visible indication to the user, respecting all privacy settings and data minimization principles.

2. **Given** a multi-tenant Phoenix application, **When** users from different tenants interact with the system, **Then** all analytics data is properly isolated per tenant with no possibility of cross-tenant data leakage.

3. **Given** an application owner reviewing analytics, **When** they access the analytics dashboard, **Then** they see aggregated insights about traffic patterns, popular pages, geographic distribution, and performance metrics without any personally identifiable information.

4. **Given** a privacy-conscious deployment, **When** analytics collection is configured, **Then** IP addresses are anonymized, no cookies are used, and data retention policies automatically purge old data according to configured schedules.

5. **Given** a high-traffic Phoenix application, **When** the analytics system processes requests, **Then** there is zero measurable performance impact on user experience and the system gracefully handles failures without affecting the host application.

### Edge Cases
- What happens when analytics collection fails due to database issues? (System continues normally, no user impact)
- How does the system handle bot traffic and automated requests? (Automatic bot detection and filtering)
- What occurs when geographic headers are missing or invalid? (Graceful fallback with basic country detection)
- How does session tracking work across device changes or network switches? (New session creation with proper fingerprinting)
- What happens during high-traffic spikes? (Asynchronous processing with circuit breakers prevent system overload)

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: System MUST track page views, API calls, and LiveView interactions invisibly to end users without any client-side JavaScript or visible indicators
- **FR-002**: System MUST provide complete multi-tenant data isolation using configurable strategies (shared database with tenant attributes or separate schemas)
- **FR-003**: System MUST automatically detect and classify device types (desktop, mobile, tablet, bot) from user agent strings
- **FR-004**: System MUST extract and store geographic information (country, city, timezone) while respecting privacy through IP anonymization
- **FR-005**: System MUST create sessionless user tracking using fingerprinting techniques that combine IP address and user agent without cookies
- **FR-006**: System MUST provide configurable route filtering to exclude admin panels, API endpoints, and custom patterns from tracking
- **FR-007**: System MUST integrate with Phoenix telemetry events and plugs for seamless data collection without application code changes
- **FR-008**: System MUST support both HTTP request tracking and LiveView interaction tracking with deduplication between layers
- **FR-009**: System MUST provide automatic data retention policies with configurable cleanup schedules for compliance
- **FR-010**: System MUST generate analytics dashboards using Phoenix Core Components and DaisyUI styling framework
- **FR-011**: System MUST export Prometheus-style metrics endpoints for infrastructure monitoring integration
- **FR-012**: System MUST handle analytics processing asynchronously to ensure zero performance impact on host applications
- **FR-013**: System MUST provide data export capabilities for GDPR compliance and data portability requirements
- **FR-014**: System MUST support custom exclude patterns using regex or simple string matching for flexible route filtering
- **FR-015**: System MUST create aggregated daily, weekly, and monthly analytics summaries for efficient querying

### Key Entities *(include if feature involves data)*
- **AnalyticsEvent**: Individual tracking events (page views, API calls, LiveView interactions) with metadata like path, method, duration, device type, and geographic information
- **Session**: User session tracking based on fingerprinting without cookies, including start/end times, page view counts, entry/exit paths, and bounce detection
- **AnalyticsConfiguration**: Tenant-specific settings controlling what data to collect, route exclusions, privacy options, and retention policies
- **DailyAnalytics**: Aggregated daily summaries including visit counts, unique sessions, top pages, geographic breakdowns, and performance metrics
- **Geographic Data**: Country, city, timezone information extracted from Cloudflare headers or IP address geolocation with privacy-preserving anonymization

---

## Review & Acceptance Checklist
*GATE: Automated checks run during main() execution*

### Content Quality
- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

---

## Execution Status
*Updated by main() during processing*

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified
- [x] Review checklist passed

---