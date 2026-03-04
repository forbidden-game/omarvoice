import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { transitionState } from "./state-machine.js";

describe("transitionState", () => {
  it("moves idle -> recording on start", () => {
    assert.equal(transitionState("idle", "start"), "recording");
  });

  it("moves recording -> submitting on stop", () => {
    assert.equal(transitionState("recording", "stop"), "submitting");
  });

  it("moves submitting -> idle on success", () => {
    assert.equal(transitionState("submitting", "submitSuccess"), "idle");
  });

  it("moves submitting -> idle on failure", () => {
    assert.equal(transitionState("submitting", "submitFailure"), "idle");
  });

  it("rejects invalid transitions", () => {
    assert.throws(() => transitionState("idle", "stop"));
  });
});
