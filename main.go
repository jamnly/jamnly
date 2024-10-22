package main

import (
    "fmt"
    "log"
    "myfabric/fabricoperations"
)

func main() {
    // 初始化SDK
    err := fabricoperations.InitializeSDK()
    if err != nil {
        log.Fatalf("Failed to initialize SDK: %v", err)
    }

    // 创建通道
    channelID := "channel1"
    err = fabricoperations.CreateChannel(channelID, "./channel-artifacts/channel.tx")
    if err != nil {
        log.Fatalf("Failed to create channel: %v", err)
    }

    // 加入通道
    peers := []string{"cli1", "cli2", "cli3"}
    for _, peer := range peers {
        err = fabricoperations.JoinChannel(channelID, peer)
        if err != nil {
            log.Fatalf("Failed to join channel %s with peer %s: %v", channelID, peer, err)
        }
    }

    // 更新锚节点
    anchorTxs := map[string]string{
    "Org1MSP": "./channel-artifacts/Org1MSPanchors.tx",
    "Org2MSP": "./channel-artifacts/Org2MSPanchors.tx",
    "Org3MSP": "./channel-artifacts/Org3MSPanchors.tx",
    }

    for org, anchorTxPath := range anchorTxs {
    fmt.Printf("正在为组织 %s 更新锚节点，交易文件: %s\n", org, anchorTxPath)
    err = fabricoperations.UpdateAnchorPeers(channelID, org, anchorTxPath)
    if err != nil {
        log.Fatalf("Failed to update anchor peers for %s: %v", org, err)
    }

    fmt.Printf("组织 %s 的锚节点更新成功\n", org)
}


    // 安装链码
    chaincodeName := "sacc"
    chaincodeLabel := "sacc_1"
    chaincodePath := "/opt/gopath/src/github.com/hyperledger/fabric-cluster/chaincode/go/sacc"
    err = fabricoperations.InstallChaincode(peers, chaincodeName, chaincodeLabel, chaincodePath)
    if err != nil {
        log.Fatalf("Failed to install chaincode: %v", err)
    }

    // 批准链码
    orgs := []string{"Org1", "Org2", "Org3"}
    err = fabricoperations.ApproveChaincode(channelID, chaincodeName, chaincodeLabel, orgs)
    if err != nil {
        log.Fatalf("Failed to approve chaincode: %v", err)
    }
    //提交链码
    peerAddresses := []string{
    "peer0.org1.example.com:7051",
    "peer0.org2.example.com:9051",
    "peer0.org3.example.com:10051",
    }

    tlsRootCertFiles := []string{
    "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt",
    "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt",
    "/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt",
}

     err = fabricoperations.CommitChaincode(channelID, chaincodeName, peerAddresses, tlsRootCertFiles)
     if err != nil {
    log.Fatalf("Failed to commit chaincode: %v", err)
}


    fmt.Println("All Fabric operations completed successfully.")
}

