# vSphere Management + Workload Cluster E2E Test

This document is to talk about
- Subject Under Test (SUT)
- E2E Test strategy and the "Why?" behind it
-  and 

## Subject Under Test (SUT)

The subject under test for this E2E test is -

- `tanzu management-cluster create` command used to create management cluster on vSphere platform
- `tanzu cluster create` command used to create workload cluster on vSphere platform
- `tanzu management-cluster delete` command used to delete management cluster on vSphere platform
- `tanzu cluster delete` command used to delete workload cluster on vSphere platform

## E2E Test strategy and the "Why?" behind it

proxy
run commands
govc for cleanup

## Scenario

happy path Scenario we are testing

## Handling failures

any failure - use govc to cleanup

first cleanup management cluster and then cleanup workload cluster. why? as management cluster will keep reconciling to keep the workload cluster up and running, and we don't want to delete workload cluster first and then have management cluster reconcile to create the workload cluster by the time we delete the management cluster

logs to mention if manual cleanup is needed - in future we will try to have alerts - slack / for example create github issues in repo to denote manual cleanup tasks to be taken care of. or we can make the cleanup script more resilient by running it separately in another script in another workflow in the CI instead of the same workflow as the E2E tests

---

also detail out happy path and failure scenarios in the E2E Test. scenarios are not tests / test scenarios, more like what can happen when things fail. Maybe we can call it as failure path, or edge cases or just failures. Say handling failures
