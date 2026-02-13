# Camera Upgrade TODO

This checklist tracks incremental upgrades to the Godot 4.x Camera3D rig for a recoil-physics game. Each step preserves existing behavior before moving on.

---

## 1. Move camera logic to _physics_process(delta)
- Implement: Move all camera update logic from _process to _physics_process.
- Debug/Verify: Camera updates smoothly, no jitter; matches previous _process results.
- Notes: Use physics delta for all calculations.

## 2. Add state machine (DRIFT, LAUNCH, IMPACT_STABILIZE)
- Implement: Add speed thresholds, hysteresis timers, and impact triggers for state transitions.
- Debug/Verify: Camera switches states correctly based on speed and impacts; transitions are smooth.
- Notes: Use @export vars for thresholds/timers.

## 3. Blend direction on XZ plane
- Implement: Blend velocity and aim direction, with weights per state.
- Debug/Verify: Camera follows blended direction; fallback to aim when nearly stopped.
- Notes: Use normalize, lerp, and fallback logic.

## 4. Dynamic zoom, yaw cap, lookAhead, and damping per state
- Implement: Adjust zoom, yaw cap, lookAhead, and damping based on camera state; clamp values as needed.
- Debug/Verify: Camera zooms and rotates responsively; settings change per state.
- Notes: Group @export vars for tuning.

## 5. API hooks: set_slow_time(enabled), on_fired(), on_impact(impulse)
- Implement: Add hooks to adjust camera behavior as described; effects are subtle and temporary.
- Debug/Verify: Hooks adjust camera behavior as described; effects are subtle and temporary.
- Notes: Preserve existing camera API, add new hooks.

## 6. Wall-safe camera (ray/sphere cast)
- Implement: Use ray/sphere cast from target to desired camera position; smooth correction, no popping.
- Debug/Verify: Camera avoids clipping into walls; correction is smooth.
- Notes: Expose collision mask, radius, buffer as @export vars.

## 7. Keep horizon level (no roll)
- Implement: Ensure camera never rolls; blend only on XZ plane.
- Debug/Verify: Camera never rolls; horizon remains stable.
- Notes: Use look_at with up vector, ignore roll.

## 8. Optimize for mobile
- Implement: Avoid per-frame allocations, minimize debug prints.
- Debug/Verify: No performance spikes; prints only for debugging.
- Notes: Use preallocated variables, avoid spam.

## 9. Group all @export vars for tuning
- Implement: Organize all tuning parameters for easy adjustment.
- Debug/Verify: All tuning parameters are easy to find and adjust.
- Notes: Add comments and organize exports.

---

Check off each step as you complete it. Preserve existing camera behavior before moving to the next item.