export type VoiceState = "idle" | "recording" | "submitting";

export type VoiceEvent = "start" | "stop" | "submitSuccess" | "submitFailure";

const TRANSITIONS: Record<VoiceState, Partial<Record<VoiceEvent, VoiceState>>> = {
  idle: {
    start: "recording"
  },
  recording: {
    stop: "submitting"
  },
  submitting: {
    submitSuccess: "idle",
    submitFailure: "idle"
  }
};

export function transitionState(current: VoiceState, event: VoiceEvent): VoiceState {
  const next = TRANSITIONS[current][event];

  if (!next) {
    throw new Error(`Invalid state transition: ${current} -> ${event}`);
  }

  return next;
}
