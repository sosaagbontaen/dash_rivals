# DOCUMENT 1 — Track Racing Game POC

## Project

Build a **mobile 3D track-and-field racing game prototype for iOS**.

The long-term vision is to create the track-racing game that track fans wish existed: a
highly immersive, visually impressive sprinting experience that makes the player feel like
they are **inside a real 100m race**, while eventually expanding into a much broader
track-and-field universe.

This is currently a **proof of concept**, not a production game. The goal is NOT to build
a complete game. The goal is to answer one question:

> **Can a short 100m race on an iPhone feel so immersive and satisfying that the player
> immediately wants to run another race?**

## Inspiration

### 1. First-person / POV sprint videos

POV race footage (including Meta Ray-Ban glasses recordings) creates the sensation
**"I feel like I'm actually running."** The viewer sees competitors, feels the speed,
watches the track move beneath them. The game should capture this **visceral feeling of
speed and participation**.

### 2. MotionAthlete-style race simulations

Cinematic 3D simulations of track races that feel almost like a broadcast of a real
sporting event. The game should capture this **spectacle**: realistic-looking stadium,
athletes, broadcast-style presentation, dramatic cameras, splits, photo finishes, replays.

**Do not use real athletes in the POC.** All athletes must be fictional and original.

### 3. Speed Stars

Demonstrates that sprint mechanics alone create a compelling mobile loop:
**Race → see time → improve → race again.** Learn from its game-design principles
(simple touch input with skillful timing, PBs, ghosts), but do not copy its
implementation or visual identity.

# POC Scope — ONLY build:

- **Event:** 100m sprint
- **Environment:** one outdoor stadium — large, energetic, prestigious. Packed crowd,
  stadium lighting, track surface, starting blocks, finish line, lane markings,
  scoreboard, background activity where practical.
- **Athletes:** 8 fictional sprinters, each with unique appearance, name, country, lane,
  and performance characteristics. Original identities only.

# Core Gameplay

The player controls one sprinter.

**SET → START → ACCELERATE → MAINTAIN MAX SPEED → FINISH → SEE TIME/PLACEMENT → RUN AGAIN**

Simple touch input with skillful timing. The mechanic must produce a meaningful
difference between bad, decent, and excellent execution. The player should feel:
**"I know I can run that faster."** That feeling is the core retention mechanism.

# Sprint Model

Three conceptual phases: (1) start/acceleration, (2) maximum velocity, (3) speed
maintenance. Physics need to **feel believable**, not be scientifically perfect.

# Camera

Extremely important. Experiment with a **near-POV / immersive camera**. The player should
see: their body, the track, competitors, the stadium, the finish line. The camera must
communicate speed. **One excellent gameplay camera is more important than five mediocre
cameras.** Optional extras: broadcast cam, finish cam, replay cam.

# Race Presentation

Athletes walk to blocks → camera introduces field → SET → gun → race → finish → times →
winner celebration → results. Keep it short — the player should reach the race quickly.

# Results

- YOUR TIME (e.g. 10.24), PLACE (e.g. 3rd)
- SPLITS: 50m / 100m
- NEW PB when applicable
- **RUN AGAIN** as the primary action

# Fictional Performance System / AI

Each AI athlete has different characteristics (reaction, acceleration, top speed, speed
endurance) plus small variability, so races develop differently — racing **people**, not
identical bots. Deterministic/parameterized profiles; no ML.

# Audio

Audio matters enormously: stadium ambience, crowd, start commands, gun (should feel like
a **moment**), footsteps, breathing, finish reaction, subtle UI sounds.

# Visual Priority

1. Athlete animation
2. Camera / sense of speed
3. Track + stadium
4. Lighting
5. Crowd
6. UI

A beautiful UI cannot rescue a race that doesn't feel good.

# POC Non-Goals

Do NOT build: real athletes/licensing, multiplayer, accounts, backend, global
leaderboards, monetization, ads, IAP, career mode, progression, extra events, extra
stadiums, complex customization, social features, live services. Do not prematurely
architect for these.

# Technical Philosophy

Build the smallest technically reasonable prototype. Prefer **working + fun + visually
impressive** over **architecturally perfect + unfinished**.

# Success Criterion

After completing a race, the immediate emotional response should be:

> **"That was sick. Let me run it again."**

The only metric that matters: **Does the race feel good?**
