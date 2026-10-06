# Concepts

The building blocks: components, profiles, environments, state, inventory and the configuration order.

!!! note "Coming in the full documentation"
    This page is part of the prototype navigation. Its content is written in the next phase.
    Until then, the current guide:

    - [Profiles guide](https://github.com/bhumi46/infra/blob/GH-issue-273-v2/docs/PROFILES.md)
    - [Deployment sequence](https://github.com/bhumi46/infra/blob/GH-issue-273-v2/docs/DEPLOYMENT_SEQUENCE.md)

## Components

Five Terraform components plus `vm`, each with its own state.

## Profiles

Deployment shapes — `mosip`, `esignet-standalone`, `observ` — in `profiles/<name>/`.

## Environments

One Git branch = one environment (state, secrets, settings).

## State

One state file per component × profile × branch.

## Inventory

One format, produced from Terraform outputs or `hosts.yml`.
