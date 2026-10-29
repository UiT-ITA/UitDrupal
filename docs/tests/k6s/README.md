# k6 tests

## Install

```sh
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

## Running

Create a new script:
```sh
k6 new
```
This will create a new `script.js` in current directory.

Run k6:
```sh
k6 run script.js
```

Add Virtual Users (VU)
```sh
k6 run --vus 10 --duration 30s script.js
```
Run a 30 second load test.

For more info, see k6's [getting started](https://grafana.com/docs/k6/latest/get-started/running-k6/)
