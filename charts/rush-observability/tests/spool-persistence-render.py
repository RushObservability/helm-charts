"""Assert storage ownership and rollout contracts in actual Helm manifests."""
from pathlib import Path
import subprocess

import yaml

CHART = Path(__file__).resolve().parents[1]
STACK = CHART.parent / 'rush-observability-stack'
HA = {
    'queryApi.workloadKind': 'StatefulSet',
    'queryApi.replicas': '3',
    'clickhouse.mode': 'operator',
    'clickhouse.enabled': 'true',
    'clickhouse.keeper.enabled': 'true',
    'queryApi.config.ingest.buffer.backend': 'object_store',
    'queryApi.config.ingest.buffer.objectStore.bucket': 'test-buffer',
    'queryApi.config.ingest.buffer.objectStore.credentialsSecret.name': 'buffer-credentials',
    'queryApi.networkPolicy.allowExternalHttpsEgress': 'true',
    'queryApi.drainWorker.enabled': 'true',
}


def render(values=None, *, chart=CHART, rejected=None, release='spool'):
    command = ['helm', 'template', release, str(chart)]
    for key, value in (values or {}).items():
        command.extend(['--set', f'{key}={value}'])
    result = subprocess.run(command, text=True, capture_output=True)
    if rejected:
        assert result.returncode != 0, f'unsafe values were accepted: {values}'
        assert rejected in result.stderr, result.stderr
        return []
    assert result.returncode == 0, result.stderr
    return [doc for doc in yaml.safe_load_all(result.stdout) if doc]


def resource(docs, kind, name):
    matches = [doc for doc in docs if doc['kind'] == kind and doc['metadata']['name'] == name]
    assert len(matches) == 1, (kind, name, len(matches))
    return matches[0]


def volumes(workload):
    return {v['name']: v for v in workload['spec']['template']['spec']['volumes']}


def claims(workload):
    return {v['metadata']['name']: v for v in workload['spec'].get('volumeClaimTemplates', [])}


def assert_retained(pvc, size):
    assert pvc['metadata']['annotations']['helm.sh/resource-policy'] == 'keep'
    assert pvc['spec']['resources']['requests']['storage'] == size
    assert pvc['spec']['accessModes'] == ['ReadWriteOnce']


defaults = render()
api = resource(defaults, 'Deployment', 'spool-query-api')
assert api['spec']['replicas'] == 1
assert api['spec']['strategy'] == {'type': 'Recreate'}
assert volumes(api)['rush-spool']['persistentVolumeClaim']['claimName'] == 'spool-query-api-ingest'
assert volumes(api)['audit-spool']['persistentVolumeClaim']['claimName'] == 'spool-query-api-audit'
assert [c['name'] for c in api['spec']['template']['spec']['initContainers']] == ['prepare-audit-spool', 'prepare-rush-spool']
default_env = {v['name']: v.get('value') for v in api['spec']['template']['spec']['containers'][0]['env']}
assert default_env['RUSH_SPOOL_DIR'] == '/var/lib/rush/spool/queue'
for name, size in [('spool-query-api-ingest', '4Gi'), ('spool-query-api-audit', '1Gi')]:
    pvc = resource(defaults, 'PersistentVolumeClaim', name)
    assert_retained(pvc, size)
    assert 'storageClassName' not in pvc['spec']

custom = render({
    'queryApi.ingestSpoolPersistence.storageClass': 'fast',
    'queryApi.ingestSpoolPersistence.size': '8Gi',
    'queryApi.auditSpoolPersistence.storageClass': '-',
})
assert resource(custom, 'PersistentVolumeClaim', 'spool-query-api-ingest')['spec'] == {
    'accessModes': ['ReadWriteOnce'], 'storageClassName': 'fast',
    'resources': {'requests': {'storage': '8Gi'}},
}
assert resource(custom, 'PersistentVolumeClaim', 'spool-query-api-audit')['spec']['storageClassName'] == ''

existing = render({
    'queryApi.ingestSpoolPersistence.existingClaim': 'old-ingest',
    'queryApi.auditSpoolPersistence.existingClaim': 'old-audit',
})
existing_api = resource(existing, 'Deployment', 'spool-query-api')
assert volumes(existing_api)['rush-spool']['persistentVolumeClaim']['claimName'] == 'old-ingest'
assert volumes(existing_api)['audit-spool']['persistentVolumeClaim']['claimName'] == 'old-audit'
assert not any(doc['kind'] == 'PersistentVolumeClaim' for doc in existing)

ephemeral = render({
    'queryApi.ingestSpoolPersistence.enabled': 'false',
    'queryApi.auditSpoolPersistence.enabled': 'false',
})
ephemeral_api = resource(ephemeral, 'Deployment', 'spool-query-api')
assert volumes(ephemeral_api)['rush-spool']['emptyDir'] == {}
assert volumes(ephemeral_api)['audit-spool']['emptyDir'] == {}

stateful = render({'queryApi.workloadKind': 'StatefulSet'})
stateful_api = resource(stateful, 'StatefulSet', 'spool-query-api')
assert set(claims(stateful_api)) == {'rush-spool', 'audit-spool'}
assert 'rush-spool' not in volumes(stateful_api)
assert 'audit-spool' not in volumes(stateful_api)
assert claims(stateful_api)['rush-spool']['spec']['resources']['requests']['storage'] == '4Gi'
# A singleton can reattach old Deployment claims during a controlled migration.
stateful_existing = render({
    'queryApi.workloadKind': 'StatefulSet',
    'queryApi.ingestSpoolPersistence.existingClaim': 'old-ingest',
    'queryApi.auditSpoolPersistence.existingClaim': 'old-audit',
})
stateful_existing_api = resource(stateful_existing, 'StatefulSet', 'spool-query-api')
assert claims(stateful_existing_api) == {}
assert volumes(stateful_existing_api)['audit-spool']['persistentVolumeClaim']['claimName'] == 'old-audit'

ha = render(HA)
ha_api = resource(ha, 'StatefulSet', 'spool-query-api')
assert ha_api['spec']['replicas'] == 3
assert ha_api['spec']['podManagementPolicy'] == 'Parallel'
assert ha_api['spec']['updateStrategy'] == {'type': 'RollingUpdate'}
assert 'strategy' not in ha_api['spec']
assert 'progressDeadlineSeconds' not in ha_api['spec']
assert set(claims(ha_api)) == {'audit-spool'}
assert claims(ha_api)['audit-spool']['spec']['accessModes'] == ['ReadWriteOnce']
assert 'audit-spool' not in volumes(ha_api)
assert volumes(ha_api)['rush-spool']['emptyDir'] == {}
assert 'persistentVolumeClaimRetentionPolicy' not in ha_api['spec']  # Kubernetes default is Retain.
headless = resource(ha, 'Service', ha_api['spec']['serviceName'])
assert headless['spec']['clusterIP'] == 'None'
assert headless['spec']['selector'] == ha_api['spec']['selector']['matchLabels']
service = resource(ha, 'Service', 'spool-query-api')
assert service['spec']['selector'] == headless['spec']['selector']
worker = resource(ha, 'Deployment', 'spool-query-api-drain-worker')
assert worker['spec']['strategy'] == {'type': 'Recreate'}
assert volumes(worker)['audit-spool']['persistentVolumeClaim']['claimName'] == 'spool-drain-worker-audit'
assert_retained(resource(ha, 'PersistentVolumeClaim', 'spool-drain-worker-audit'), '1Gi')
assert not any(doc['kind'] == 'PersistentVolumeClaim' and doc['metadata']['name'] == 'spool-query-api-audit' for doc in ha)
for workload in [ha_api, worker]:
    env = {v['name']: v.get('value') for v in workload['spec']['template']['spec']['containers'][0]['env']}
    assert env['RUSH_BUFFER_REQUIRE_OBJECT_STORE'] == 'true'
    assert env['RUSH_AUDIT_SPOOL_DIR'] == '/var/lib/rush/audit-spool/outbox'
    init = workload['spec']['template']['spec']['initContainers'][0]
    assert '@sha256:' in init['image']
    assert init['securityContext']['runAsUser'] == 999
    assert init['securityContext']['capabilities']['drop'] == ['ALL']
    assert init['securityContext']['readOnlyRootFilesystem'] is True
    assert init['volumeMounts'] == [{'name': 'audit-spool', 'mountPath': '/var/lib/rush/audit-spool'}]

# Replica count and pod configuration changes must preserve claim identity.
scaled = resource(render({**HA, 'queryApi.replicas': '1', 'queryApi.podAnnotations.revision': 'next'}), 'StatefulSet', 'spool-query-api')
assert claims(scaled) == claims(ha_api)
assert scaled['spec']['serviceName'] == ha_api['spec']['serviceName']

render({**HA, 'queryApi.workloadKind': 'Deployment'}, rejected='require queryApi.workloadKind=StatefulSet')
render({**HA, 'queryApi.auditSpoolPersistence.existingClaim': 'shared'}, rejected='existingClaim requires one replica')
render({'queryApi.rollout.strategy': 'RollingUpdate'}, rejected='strategy=Recreate')
render({**HA, 'queryApi.drainWorker.rollout.strategy': 'RollingUpdate',
        'queryApi.drainWorker.rollout.maxSurge': '1',
        'queryApi.drainWorker.rollout.maxUnavailable': '0'}, rejected='drainWorker.rollout.strategy must be Recreate')
render({
    'queryApi.config.runtime.environment': 'production',
    'queryApi.config.runtime.baseUrl': 'https://rush.example.test',
    'queryApi.ingestSpoolPersistence.enabled': 'false',
}, rejected='production disk ingest requires')
render({
    'queryApi.ingestSpoolPersistence.existingClaim': 'shared',
    'queryApi.auditSpoolPersistence.existingClaim': 'shared',
}, rejected='must use different existingClaim')
render({**HA, 'queryApi.replicas': '1', 'queryApi.auditSpoolPersistence.existingClaim': 'shared',
        'queryApi.drainWorker.auditSpoolPersistence.existingClaim': 'shared'}, rejected='worker must have its own audit claim')
render({**HA, 'queryApi.drainWorker.auditSpoolPersistence.existingClaim': 'audit-spool-spool-query-api-2'},
       rejected='worker must have its own audit claim')
render({'queryApi.workloadKind': 'StatefulSet',
        'queryApi.ingestSpoolPersistence.existingClaim': 'audit-spool-spool-query-api-0'},
       rejected='must use different existingClaim')
render({'queryApi.workloadKind': 'DaemonSet'}, rejected='queryApi.workloadKind')
render({'queryApi.ingestSpoolPersistence.accessModes[0]': 'ReadOnlyMany'}, rejected='accessModes')

# Keep the headless service distinct from the client service at Helm's name limit.
long_release = 'r' * 53
long_docs = render(HA, release=long_release)
long_api = resource(long_docs, 'StatefulSet', long_release + '-query-api')
assert long_api['spec']['serviceName'] != long_api['metadata']['name']
assert len(long_api['spec']['serviceName']) <= 63
resource(long_docs, 'Service', long_api['spec']['serviceName'])

# The packaged dependency of the umbrella chart must carry the same fix.
stack = render(chart=STACK)
stack_api = resource(stack, 'Deployment', 'spool-query-api')
assert stack_api['spec']['strategy'] == {'type': 'Recreate'}
assert volumes(stack_api)['rush-spool']['persistentVolumeClaim']['claimName'] == 'spool-query-api-ingest'
stack_ha = render({('rush.' + key if key.startswith('queryApi.') or key.startswith('clickhouse.') else key): value
                   for key, value in HA.items()}, chart=STACK)
assert set(claims(resource(stack_ha, 'StatefulSet', 'spool-query-api'))) == {'audit-spool'}
print('spool persistence, ownership, rollout, and stack render regressions passed')
