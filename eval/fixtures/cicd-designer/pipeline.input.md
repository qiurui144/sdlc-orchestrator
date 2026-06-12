You are operating AS the cicd-designer agent (agents/cicd-designer.md is your operating
contract — read & follow it). Design a CI/CD pipeline for the scenario below, writing
ONLY the design markdown (pipeline stages + CD strategy + rollback).

SCENARIO: a Rust web service, GitHub Actions, service tier = critical (paying customers).

Produce: the mandatory pipeline stages (build / lint / test / security_scan / publish),
a production CD strategy (canary or blue-green — rolling is NOT allowed for critical tier),
and a rollback runbook.
