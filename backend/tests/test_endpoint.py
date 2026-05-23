import requests

url = 'http://10.60.121.199:8000/api/repository/vault/'
print(f'Testing URL: {url}')

try:
    response = requests.get(url)
    print(f'Status: {response.status_code}')
    if response.status_code == 200:
        data = response.json()
        print(f'Entries: {len(data.get("entries", []))}')
        print(f'Counts: {data.get("counts")}')
        if data.get('entries'):
            print('\nFirst entry:')
            entry = data['entries'][0]
            for key, value in entry.items():
                print(f'{key}: {value}')
    else:
        print(f'Response: {response.text[:200]}')
except Exception as e:
    print(f'Error: {e}')
