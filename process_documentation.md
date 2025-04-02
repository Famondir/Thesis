# Process documentation

## Kubenetes Tutorial

### First app

At [first app](https://docs.cluster.ris.bht-berlin.de/user/firstapp/) the command 
```
kubectl exec -it firstpod bash
```

is given. But for me it only worked after i added a `--` in front of the `bash`:

```
kubectl exec -it firstpod -- bash
```

The shell is exited with the command `exit`.

In [Headlamp](https://dashboard.cluster.ris.bht-berlin.de/c/main/) I have no permissions.