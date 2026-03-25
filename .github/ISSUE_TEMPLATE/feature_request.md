---
name: 🚀 Feature Request
about: Use this template to define a new feature using the HeyU narrative-driven process.
title: '[Feature] '
labels: enhancement
assignees: ''
---

## **📖 User Story**
**As a** [type of user],
**I want to** [action],
**so that** [outcome/emotional payoff].

---

## **🎭 Narrative**
*Write a step-by-step journey of how the user experiences this feature. Include emotions, interactions, and the "magic moments."*
Example:
> *Alex joins HeyU feeling shy. The app suggests a "Draw Together" game. Alex draws a boat. Lexi adds waves and says, "You drew something that carries others—that’s leadership." Alex adds a sail. After the game, Alex gets a White Belt: "For guiding and adapting." Alex feels seen and curious about the next step.*

---

## **🔧 Functional Requirements**
*List what the system MUST do to make the narrative real. Number each requirement (FR-1, FR-2,...).*
Example:
1. System must provide a real-time collaborative drawing canvas.
2. Lexi must analyze the user’s drawing and provide personalized feedback.
3. System must award a White Belt after the game, referencing the user’s actions.

---

## **💻 Technical Requirements**
*Map each functional requirement to a technical solution. Include trade-offs or open questions.*
   Functional Requirement | Technical Solution               | Notes                          |
 |-----------------------|-----------------------------------|--------------------------------|
 | FR-1                  | Phoenix LiveView + SVG/Canvas API | Real-time updates for drawing. |
 | FR-2                  | OpenRouter (Mistral-7B) + prompt  | Prompt: "Analyze this drawing..." |
 | FR-3                  | Elixir rules engine + pgvector    | Tie belt logic to game data.  |

---

## **📝 Details & Open Questions**
*Add specifics like API endpoints, database schemas, or unanswered questions.*
Example:
- **Prompt for Lexi’s feedback**:
  ```plaintext
  Analyze this drawing for personality traits. Respond in 1-2 warm, specific sentences.
  Drawing description: [USER_DRAWING]
  User’s past behaviors: [USER_DATA]
