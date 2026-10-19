"""Run the rendered init command as UID 999 against a root-owned volume."""
from pathlib import Path
import subprocess
import uuid

import yaml

chart = Path(__file__).resolve().parents[1]
rendered = subprocess.check_output([
    'helm', 'template', 'init-test', str(chart),
    '--show-only', 'templates/query-api-deployment.yaml',
], text=True)
pod = yaml.safe_load(rendered)['spec']['template']['spec']


def run(script, *, user='999:999', success=True):
    command = ['docker', 'run', '--rm', '-i', '--user', user,
               '--read-only', '--security-opt', 'no-new-privileges',
               '--mount', f'type=volume,source={volume},target={root}']
    if user == '999:999':
        command += ['--cap-drop', 'ALL']
    result = subprocess.run(command + [init['image'], '/bin/sh', '-ec', script],
                            text=True, capture_output=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr


for init in pod['initContainers']:
    volume = 'rush-spool-init-test-' + uuid.uuid4().hex
    root = init['volumeMounts'][0]['mountPath']
    directory, extension = ('outbox', 'json') if 'audit' in init['name'] else ('queue', 'spool')
    target = f'{root}/{directory}'
    filename = '0001-event.' + extension
    subprocess.run(['docker', 'volume', 'create', volume], check=True, capture_output=True)
    try:
        # fsGroup makes the root writable by the app but does not transfer ownership.
        run(f'chown 0:999 {root}; chmod 770 {root}', user='0:0')
        run(f'printf legacy > {root}/{filename}; chmod 600 {root}/{filename}')
        run(init['args'][0])
        run(f'''
            test "$(stat -c %u {root})" = 0
            test "$(stat -c %u {target})" = 999
            test "$(stat -c %a {target})" = 700
            test "$(cat {target}/{filename})" = legacy
            test ! -e {root}/{filename}
            chmod 700 {target}
        ''')
        # Re-running after a pod restart preserves the recovered records.
        run(init['args'][0])
        run(f'test "$(cat {target}/{filename})" = legacy')

        # A partially migrated volume with a collision must stop without clobbering.
        run(f'printf conflict > {root}/{filename}')
        run(init['args'][0], success=False)
        run(f'''
            test "$(cat {root}/{filename})" = conflict
            test "$(cat {target}/{filename})" = legacy
            rm {root}/{filename}
            ln -s {directory}/{filename} {root}/linked.{extension}
        ''')
        run(init['args'][0], success=False)
        run(f'rm {root}/linked.{extension}; mv {target} {root}/saved; ln -s saved {target}')
        run(init['args'][0], success=False)
        print(f'{init["name"]}: migration, non-root permissions, restart, and conflict tests passed')
    finally:
        subprocess.run(['docker', 'volume', 'rm', volume], check=True, capture_output=True)
