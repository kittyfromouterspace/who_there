# Implementation Plan: WhoThere - Phoenix Analytics Library

**Branch**: `001-we-have-a` | **Date**: 2025-09-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/home/lenz/code/who_there/specs/001-we-have-a/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path ✓
2. Fill Technical Context (scan for NEEDS CLARIFICATION) ✓
3. Fill the Constitution Check section ✓
4. Evaluate Constitution Check section ✓
5. Execute Phase 0 → research.md ✓
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, AGENTS.md ✓
7. Re-evaluate Constitution Check section ✓
8. Plan Phase 2 → Describe task generation approach ✓
9. STOP - Ready for /tasks command ✓
```

**IMPORTANT**: The /plan command STOPS at step 8. Phase 2 is executed by the /tasks command.

## Summary
WhoThere is a privacy-first, multi-tenant Phoenix analytics library that provides invisible server-side tracking of page views, API calls, and LiveView interactions. The library integrates seamlessly with Phoenix applications using plugs and telemetry events, stores data through Ash Framework resources with PostgreSQL, and presents analytics through DaisyUI-styled dashboards with D3.js visualizations. Key features include bot traffic segregation, automatic proxy header detection, Phoenix Presence integration for user identity, and specialized LiveView dead render deduplication.

## Technical Context
**Language/Version**: Elixir 1.18+ with Phoenix Framework 1.8+
**Primary Dependencies**: Ash Framework 3.x+, AshPostgres, DaisyUI, D3.js for visualizations
**Storage**: PostgreSQL with Ash.Postgres data layer for analytics storage
**Testing**: ExUnit for unit tests, Phoenix.ConnTest/Phoenix.LiveViewTest for integration testing
**Target Platform**: Phoenix web applications (single-tenant and multi-tenant)
**Project Type**: Elixir library for Phoenix applications
**Performance Goals**: Zero measurable impact on host application performance, <1ms analytics overhead
**Constraints**: Complete user privacy (no cookies, anonymized IPs), multi-tenant data isolation, asynchronous processing only
**Scale/Scope**: Support for high-traffic Phoenix applications, configurable data retention, bot detection and segregation

**Additional User Requirements**:
- Use D3.js for advanced data visualizations and fancy charts
- Automatically detect popular proxy headers (Cloudflare, AWS ALB, nginx, etc.) for accurate geographic data
- Show bot traffic separately with per-bot breakdowns and exclude from normal user metrics
- Integrate with Phoenix Presence for logged-in user tracking when available
- Handle LiveView dead render deduplication (only count connected LiveView renders, not initial dead renders)
- Use Igniter (https://hexdocs.pm/igniter/readme.html) as the preferred installation and setup mechanism

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

✅ **Phoenix Analytics Library Foundation**: Library is designed as standalone, self-contained Elixir package
✅ **Invisible Server-Side Monitoring**: No client-side JavaScript, uses Phoenix plugs and telemetry only
✅ **Test-First Development**: TDD approach with ExUnit and Phoenix testing frameworks
✅ **Ash Framework Analytics Domain**: All business logic through Ash 3.x+ resources and domains
✅ **Privacy-First Data Collection**: IP anonymization, no PII storage, data retention policies
✅ **Multi-Tenant Architecture**: Tenant isolation via Ash multitenancy features
✅ **Required Technology Stack**: Phoenix 1.8+, Ash 3.x+, PostgreSQL, DaisyUI, ExUnit
✅ **Forbidden Patterns**: No client-side tracking, no direct Ecto queries, no GenServer for collection
✅ **Performance Requirements**: Asynchronous processing, circuit breakers, zero user impact
✅ **Quality Standards**: mix check, mix format, proper indexing, tenant isolation testing

**PASS** - All constitutional requirements satisfied

## Project Structure

### Documentation (this feature)
```
specs/001-we-have-a/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command) ✓
├── data-model.md        # Phase 1 output (/plan command) ✓
├── quickstart.md        # Phase 1 output (/plan command) ✓
├── contracts/           # Phase 1 output (/plan command) ✓
│   ├── analytics_domain.ex
│   ├── analytics_event.ex
│   ├── session.ex
│   ├── analytics_configuration.ex
│   └── daily_analytics.ex
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# Elixir library structure
lib/
├── who_there/
│   ├── domain.ex               # Ash domain
│   ├── resources/              # Ash resources
│   │   ├── analytics_event.ex
│   │   ├── session.ex
│   │   ├── analytics_configuration.ex
│   │   └── daily_analytics.ex
│   ├── plugs/                 # Phoenix plugs
│   │   └── request_tracker.ex
│   ├── telemetry.ex           # Telemetry handlers
│   ├── session_tracker.ex     # Session utilities
│   ├── geo_parser.ex          # Geographic parsing
│   ├── route_filter.ex        # Route filtering
│   ├── queries/               # Analytics queries
│   ├── jobs/                  # Background jobs
│   └── live/                  # LiveView dashboards
├── who_there.ex               # Main module

priv/
└── repo/
    └── migrations/            # Database migrations

test/
├── who_there/
│   ├── resources/             # Resource tests
│   ├── plugs/                 # Plug tests
│   ├── queries/               # Query tests
│   └── integration/           # Integration tests
└── support/                   # Test helpers
```

**Structure Decision**: Single Elixir library project with Phoenix integration

## Phase 0: Outline & Research ✓

### Research Findings

**D3.js Integration Decision**:
- **Decision**: Use D3.js v7 with Phoenix LiveView hooks for client-side rendering
- **Rationale**: D3.js provides superior data visualization capabilities vs server-side charts, LiveView hooks enable seamless integration
- **Alternatives considered**: Server-side SVG generation (limited interactivity), Chart.js (less flexible), Phoenix built-in charts (basic)

**Proxy Header Detection Decision**:
- **Decision**: Comprehensive header parsing with priority-based fallbacks
- **Rationale**: Different CDNs/proxies use different headers, need robust detection for accurate geolocation
- **Headers to support**: Cloudflare (cf-*), AWS ALB (x-forwarded-*), nginx (x-real-ip), standard (x-forwarded-for)

**Bot Traffic Segregation Decision**:
- **Decision**: Multi-tier bot detection with separate analytics streams
- **Rationale**: Bot traffic should be analyzed separately and excluded from user metrics for accuracy
- **Detection methods**: User-agent patterns, behavior analysis, known bot IP ranges, request patterns

**Phoenix Presence Integration Decision**:
- **Decision**: Optional Presence integration with graceful fallback to session tracking
- **Rationale**: Presence provides accurate user identity when available, session fingerprinting as fallback
- **Implementation**: Check for Presence availability, use presence_id when available, fingerprint otherwise

**LiveView Deduplication Decision**:
- **Decision**: Track only connected LiveView renders using socket.connected? flag
- **Rationale**: Dead renders are just HTTP requests and should not be double-counted as LiveView interactions
- **Implementation**: Telemetry handlers check connection status before tracking events

## Phase 1: Design & Contracts ✓

Generated artifacts:
- `data-model.md`: Complete entity definitions with Ash resource specifications
- `contracts/`: Ash domain and resource contracts with actions and policies
- `quickstart.md`: Step-by-step integration guide for Phoenix applications
- `AGENTS.md`: Updated context for AI development assistance

All functional requirements mapped to Ash resources and actions with tenant isolation and privacy protections.

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each Ash resource → resource creation task + tests [P]
- Each plug/telemetry handler → implementation task + tests [P]
- Each user story → integration test task
- D3.js visualization components → frontend tasks
- Bot detection → specialized analytics tasks
- Presence integration → user tracking tasks
- LiveView deduplication → telemetry tasks

**Ordering Strategy**:
- TDD order: Tests before implementation
- Dependency order: Resources before domain before plugs before UI
- Analytics pipeline: Collection → storage → processing → display
- Mark [P] for parallel execution (independent components)

**Estimated Output**: 35-40 numbered, ordered tasks including:
1. Core Ash resources and domain setup
2. Phoenix plugs and telemetry handlers
3. Bot detection and traffic segregation
4. Geographic data processing
5. Session tracking and Presence integration
6. LiveView deduplication logic
7. D3.js dashboard components
8. Integration tests and quickstart validation

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*No constitutional violations requiring justification*

## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented (N/A)

---
*Based on WhoThere Analytics Constitution v1.0.0 - See `.specify/memory/constitution.md`*