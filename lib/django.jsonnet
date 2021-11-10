local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local deployment = k.apps.v1.deployment;
local container = k.core.v1.container;
local port = k.core.v1.containerPort;
local service = k.core.v1.service;
local withInitContainers = deployment.spec.template.spec.withInitContainers;
local withArgs = container.withArgs;
local withImagePullSecrets = deployment.spec.template.spec.withImagePullSecrets;

{
  new(name, image, envMap, imagePullSecrets, celery=false): {
    local containers = container.new(name, image) +
                       container.withImagePullPolicy('Always') +
                       container.withVolumeMounts([{
                         name: 'staticfiles',
                         mountPath: '/app/staticfiles',
                       }]) +
                       container.withEnvMap(envMap),
    local webArgs = withArgs(['config.wsgi', '--bind=0.0.0.0:80']),
    local webContainer = containers + container.withPorts([port.new('http', 80)]) +
                         container.withCommand(['gunicorn']) +
                         webArgs,
    local collectstaticArgs = withArgs(['collectstatic', '--no-input', '--clear']),
    local collectstatic = containers +
                          container.withName('collectstatic') +
                          container.withCommand(['./manage.py']) +
                          collectstaticArgs,
    local migrate = containers + container.withName('migrate') +
                    container.withCommand(['./manage.py']) +
                    withArgs(['migrate']),

    deployment: deployment.new(name, replicas=1, containers=webContainer)
                + withInitContainers([collectstatic, migrate])
                + deployment.spec.template.spec.withVolumes([{ name: 'staticfiles', emptyDir: {} }])
                + withImagePullSecrets({ name: imagePullSecrets }),
    service: k.util.serviceFor(self.deployment),
    [if celery then 'celery' else null]: {
      local c = container.new(name, image) +
                container.withCommand(['celery']) +
                container.withImagePullPolicy('Always') +
                container.withEnvMap(envMap),
      local celeryWorker = c +
                           withArgs(['--app=config.settings.celery', 'worker', '--loglevel=DEBUG']),

      local celeryBeat = c + withArgs(['--app=config.settings.celery', 'beat', '--loglevel=DEBUG']),
      worker: deployment.new(name + '-celery-worker', replicas=1, containers=celeryWorker)
              + withImagePullSecrets({ name: imagePullSecrets }),
      celeryBeat: deployment.new(name + '-celery-beat', replicas=1, containers=celeryBeat)
                  + withImagePullSecrets({ name: imagePullSecrets }),
    },
  },
}
