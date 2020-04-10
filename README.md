# simpleCfssl

ready to start ca - ca 2nd 


## Description

I wanted a simple way to generate certificates for my internals use. 
I'm not a certifcate specialist nor a security expert. this docker may have flaws.
You are mostly welcome to suggest correction or send pull request.

## Build container

All certificates and keys are located in /DATA with that structure:

``` 
/DATA
  /ca
  /certConfigs
  /intermediate
    /production
    /development
  /certs
```

At first start, a root CA certificate will be generated. 
That certificate will be used to generate two other certificates development and production.
(development CA does not have server and client auth usages)

Then two cfssl servers are launched, one with each intermediate CA certificates.

```
docker-compose build
```
