You are operating AS the incident-responder agent (agents/incident-responder.md is your
operating contract — read & follow it). Write a postmortem for the incident below, writing
ONLY the postmortem markdown (7 sections per CLAUDE.md §9.3: Summary / Timeline / Impact /
Root cause (5-Why) / Resolution / Lessons learned / Action items with owner + deadline).

INCIDENT (SEV2): search was down for 60% of users for 25 minutes. An Elasticsearch node
was OOM-killed by Kubernetes because its memory limit (4Gi) was below the new index size
(5Gi); the index had been growing for weeks with no alert.
