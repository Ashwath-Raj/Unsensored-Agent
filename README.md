# Unsensored Agent

> **Status: Discontinued — Experimental Prototype**

Unsensored Agent was an experiment in building a local-first autonomous AI computer operator.

The objective was to transform a locally hosted language model from a conversational interface into an agent capable of planning tasks, executing tools, observing results, and operating a computer.

## Original vision

Build a self-hosted AI execution environment capable of:

- Interpreting multi-step natural-language instructions.
- Planning and executing tasks.
- Using shell and filesystem tools.
- Interacting with a graphical desktop.
- Running within an isolated Ubuntu virtual machine.
- Exposing task status and execution logs through a control plane.
- Using local LLM inference rather than depending entirely on cloud inference.

## Intended architecture

```text
User
 |
 v
Control Plane / Dashboard
 |
 v
Agent Orchestrator
 |                  |
 v                  v
Local LLM        Tool Runtime
(Ollama)         (Shell, Filesystem, GUI)
 |                  |
 +--------+---------+
          |
          v
    Isolated Ubuntu VM
          |
          v
    Observations
          |
          v
    Task Results
