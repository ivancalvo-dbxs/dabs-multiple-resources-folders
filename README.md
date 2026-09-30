# dabs-multiple-resources-folders

A Databricks Asset Bundle with two resources folders instead of one.
Files in `resources-dev/` deploy only to the `development` target.
Files in `resources-prod/` deploy only to the `production` target.
When a resource works well in development, you promote it by moving its file to `resources-prod/`.

## Layout

```
databricks.yml               # bundle, variables, targets, root include of both folders
resources-dev/
  pipeline.yml               # schema + serverless pipeline (development only)
  job.yml                    # job that refreshes the pipeline (development only)
resources-prod/
  warehouse.yml              # serverless SQL warehouse (production only)
src/
  pipeline.sql               # materialized view over samples.nyctaxi.trips
Jenkinsfile                  # production deploy
```

## How each folder is tied to one target

Two settings work together.

**1. Each resource file scopes itself with `targets:`.**
This is what decides which resources a target deploys.
`include` is only supported at the root of `databricks.yml`, not inside a target.
An `include` under a target is ignored with `Warning: unknown field: include`, and the target deploys nothing.
So `databricks.yml` includes both folders, and each file declares its own target:

```yaml
targets:
  development:        # `production` for files in resources-prod/
    resources:
      jobs:
        demo_job: ...
```

**2. Each target excludes the other folder with `sync.exclude`.**
This keeps the other folder's YAML files from being uploaded to the target's workspace folder:

```yaml
targets:
  development:
    sync:
      exclude:
        - resources-prod/*.yml
  production:
    sync:
      exclude:
        - resources-dev/*.yml
```

`sync.exclude` only controls which files get uploaded.
It does not remove resource definitions: a plain `resources:` file in `resources-dev/` would still deploy to production.
Keep the `targets:` block at the top of every resource file.

## `validate`: development vs production

The resources section of `databricks bundle validate --output json` shows exactly what each target deploys.
This is the whole point of the setup: the same bundle, two different sets of resources.

### Development

```bash
databricks bundle validate --target development --output json
```

`resources` contains only what is defined in `resources-dev/` (output trimmed to the key fields):

```json
"resources": {
  "jobs": {
    "demo_job": {
      "name": "[dev ivan_calvo] multiple-resources-folders Job",
      "tasks": [
        {
          "task_key": "run_pipeline",
          "pipeline_task": { "pipeline_id": "${resources.pipelines.demo_pipeline.id}" }
        }
      ]
    }
  },
  "pipelines": {
    "demo_pipeline": {
      "name": "[dev ivan_calvo] multiple-resources-folders Pipeline",
      "catalog": "ivancalvo_playground_catalog",
      "schema": "${resources.schemas.demo_schema.name}"
    }
  },
  "schemas": {
    "demo_schema": {
      "name": "dev_ivan_calvo_multiple_resources_folders",
      "catalog_name": "ivancalvo_playground_catalog"
    }
  }
}
```

There is no warehouse, no `run_as`, and `sync.exclude` is `["resources-prod/*.yml"]`.

### Production

```bash
BUNDLE_VAR_service_principal_id=<application id> \
  databricks bundle validate --target production --output json
```

`resources` contains only the warehouse from `resources-prod/`:

```json
"resources": {
  "sql_warehouses": {
    "project_warehouse": {
      "name": "multiple-resources-folders Warehouse",
      "cluster_size": "2X-Small",
      "warehouse_type": "PRO"
    }
  }
}
```

The job, pipeline and schema from `resources-dev/` are not there.
`run_as` is `{"service_principal_name": "<application id>"}`, and `sync.exclude` is `["resources-dev/*.yml"]`.
`${resources.*.id}` references stay unresolved in `validate` output, because IDs only exist after deploy.

## Promoting a resource to production

Promote resources that reference each other together.
`demo_job` runs `demo_pipeline`, so `job.yml` and `pipeline.yml` move as a pair.

1. Move the files:

   ```bash
   git mv resources-dev/pipeline.yml resources-dev/job.yml resources-prod/
   ```

2. In each moved file, rename `development:` to `production:`.
3. Check that the resources now show up in production only:

   ```bash
   BUNDLE_VAR_service_principal_id=<application id> databricks bundle validate -t production
   ```

4. Check that every `${resources.*}` reference in both folders points to a resource in the same folder:

   ```bash
   grep -ro '\${resources\.[a-z_]*\.[a-z_]*' resources-dev resources-prod
   ```

   `databricks bundle validate` does not catch a job promoted without its pipeline.
   The reference is left unresolved and only `databricks bundle deploy` fails.
5. Merge it to `main`, and Jenkins deploys it to production.

## Development

Deploy to the `development` target (the default) and run the job:

```bash
databricks bundle deploy
databricks bundle run demo_job
```

Development mode prefixes resource names with `[dev <your user>]` and the schema with `dev_<your user>_`, so development never touches production tables.

## Production (Jenkins)

The `Jenkinsfile` only ever runs `databricks bundle validate --target production` and `databricks bundle deploy --target production`.

Bundle variables are passed as environment variables:

| Jenkins parameter | Environment variable | Default |
|-------------------|----------------------|---------|
| `CATALOG` | `BUNDLE_VAR_catalog` | `ivancalvo_playground_catalog` |
| (the `databricks-client-id` credential) | `BUNDLE_VAR_service_principal_id` | none, required for production |

The pipeline authenticates as a service principal with OAuth.
Create two Jenkins credentials of type *Secret text*:

- `databricks-client-id`: the service principal's application ID.
- `databricks-client-secret`: an OAuth secret for that service principal.

The production target sets `run_as` to `${var.service_principal_id}`.
Jenkins fills it from `databricks-client-id`, so production runs as the same service principal that deploys it.
Development has no `run_as` and runs as the user who deploys it.

The service principal needs access to the workspace and permission to create SQL warehouses.
Production deploys go to the service principal's own folder, `/Workspace/Users/<service principal>/.bundle/multiple-resources-folders/production`.
