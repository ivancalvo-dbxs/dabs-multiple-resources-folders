# dabs-multiple-resources-folders

A Databricks Asset Bundle with two resources folders instead of one.
Files in `resources-dev/` deploy only to the `development` target.
Files in `resources-prod/` deploy only to the `production` target.
When a resource works well in development, you promote it by moving its file to `resources-prod/`.

## Layout

```
databricks.yml               # bundle, `catalog` variable, targets, root include of both folders
resources-dev/
  pipeline.yml               # schema + serverless pipeline (development only)
  job.yml                    # job that refreshes the pipeline (development only)
resources-prod/
  warehouse.yml              # serverless SQL warehouse (production only)
src/
  pipeline.sql               # materialized view over samples.nyctaxi.trips
Jenkinsfile                  # production deploy
```

## Why every resource file starts with `targets:`

`include` is only supported at the root of `databricks.yml`, not inside a target.
An `include` under a target is ignored with `Warning: unknown field: include`, and the target deploys nothing.

So `databricks.yml` includes both folders, and each file scopes itself to one target:

```yaml
targets:
  development:        # `production` for files in resources-prod/
    resources:
      jobs:
        demo_job: ...
```

## Promoting a resource to production

1. Move the file:

   ```bash
   git mv resources-dev/pipeline.yml resources-prod/pipeline.yml
   ```

2. In the moved file, rename `development:` to `production:`.
3. Check that the resource now shows up in production only:

   ```bash
   databricks bundle validate -t production
   ```

4. Merge it, and Jenkins deploys it to production.

Promote resources that reference each other together.
`demo_job` runs `demo_pipeline`, so `job.yml` and `pipeline.yml` move as a pair.
`databricks bundle validate` does not catch a job promoted without its pipeline: the `${resources.pipelines.demo_pipeline.id}` reference is simply left unresolved.

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

The pipeline authenticates as a service principal with OAuth.
Create two Jenkins credentials of type *Secret text*:

- `databricks-client-id`: the service principal's application ID.
- `databricks-client-secret`: an OAuth secret for that service principal.

The service principal needs access to the workspace and permission to create SQL warehouses.
Production deploys go to the service principal's own folder, `/Workspace/Users/<service principal>/.bundle/multiple-resources-folders/production`.
