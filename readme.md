# docker 启动fabric
## 正常情况下
* 启动容器 `docker*compose up -d`
* 创建通道、加入通道、更新锚节点、打包链码、安装链码、批准链码、提交链码。
* `./myfabric`
* 进入cli1 `docker exec -it cli1 bash`
* 初始化链码
* ```
  peer chaincode invoke \
  -o orderer.example.com:7050 \
  --isInit \
  --channelID channel1 \
  --name sacc \
  --peerAddresses peer0.org1.example.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses peer0.org2.example.com:9051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  --peerAddresses peer0.org3.example.com:10051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt \
  --tls true \
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -c '{"Args":["A","100"]}'
  ```
*设置b为300
```
  peer chaincode invoke \
  -o orderer.example.com:7050 \
  --channelID channel1 \
  --name sacc \
  --peerAddresses peer0.org1.example.com:7051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
  --peerAddresses peer0.org2.example.com:9051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
  --peerAddresses peer0.org3.example.com:10051 \
  --tlsRootCertFiles /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt \
  --tls true \
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem \
  -c '{"function":"set","Args":["b","300"]}'
```
* 查询 `peer chaincode query -C channel1 -n sacc -c '{"Args":["get","A"]}'`


## 可能修改的地方
* 要换链码或增加
* main.go中更换链码，也可以更换peer
* 在chaincode下创建新的链码
  ```
  cd /opt/gopath/src/github.com/hyperledger/fabric-cluster/chaincode/go

go env -w GOPROXY=https://goproxy.cn,direct

/go mod tity

go mod init

go mod vendor

cd /opt/gopath/src/github.com/hyperledger/fabric/peer/
```
* 
