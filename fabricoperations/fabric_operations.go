package fabricoperations

import (
    "fmt"
    "os"
    "os/exec"
    "regexp"
)

// 初始化SDK
func InitializeSDK() error {
    fmt.Println("初始化SDKInitializing Fabric SDK...")
    // 可以在此加载您的 SDK 配置文件，例如 config.yaml
    return nil
}

// 创建通道
func CreateChannel(channelID, channelTxPath string) error {
    fmt.Println("创建通道......")
    cmd := exec.Command("docker", "exec", "-i", "cli1", "bash", "-c",
        fmt.Sprintf("peer channel create -o orderer.example.com:7050 -c %s -f %s --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem", channelID, channelTxPath))
    return runCommand(cmd)
}

// 加入通道
func JoinChannel(channelID, cli string) error {
  fmt.Println("加入通道......")
    cmd := exec.Command("docker", "exec", "-i", cli, "bash", "-c",
        fmt.Sprintf("peer channel join -b /opt/gopath/src/github.com/hyperledger/fabric/peer/%s.block", channelID))
        
       // 运行创建通道命令
    if err := runCommand(cmd); err != nil {
        return err
    }

    // 复制通道区块到本地环境
    if err := exec.Command("docker", "cp", "cli1:/opt/gopath/src/github.com/hyperledger/fabric/peer/"+channelID+".block", "./").Run(); err != nil {
        return fmt.Errorf("复制通道区块到本地失败: %w", err)
    }

    // 复制通道区块到其他容器
    for _, cli := range []string{"cli2", "cli3", "cli3-1"} {
        if err := exec.Command("docker", "cp", "./"+channelID+".block", cli+":/opt/gopath/src/github.com/hyperledger/fabric/peer").Run(); err != nil {
            return fmt.Errorf("复制通道区块到 %s 失败: %w", cli, err)
        }
    }  
    return nil
}

// 更新锚节点
func UpdateAnchorPeers(channelID, orgMSP, anchorTxPath string) error {
    fmt.Println(orgMSP,"更新锚节点.....")

    var cliContainer string

    // 根据组织 MSP 切换 CLI 容器
    switch orgMSP {
    case "Org1MSP":
        cliContainer = "cli1"
    case "Org2MSP":
        cliContainer = "cli2"
    case "Org3MSP":
        cliContainer = "cli3"
    default:
        return fmt.Errorf("未知的 MSP 组织: %s", orgMSP)
    }

    // 构造并执行命令
    cmd := exec.Command("docker", "exec", "-i", cliContainer, "bash", "-c",
        fmt.Sprintf("peer channel update -o orderer.example.com:7050 -c %s -f %s --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem", channelID, anchorTxPath))

    return runCommand(cmd)
}


// 安装链码
func InstallChaincode(peers []string, chaincodeName, chaincodeLabel, chaincodePath string) error {
    // 先在第一个peer打包链码
    fmt.Println(peers[0], "打包链码.....")
    cmd := exec.Command("docker", "exec", "-i", peers[0], "bash", "-c",
        fmt.Sprintf("peer lifecycle chaincode package %s.tar.gz --path %s --label %s", chaincodeName, chaincodePath, chaincodeLabel))
    err := runCommand(cmd)
    if err != nil {
        return fmt.Errorf("链码打包失败: %v", err)
    }

    // 复制链码包到其他的peer节点
    for _, peer := range peers {
        fmt.Println("复制链码包到", peer)
        _, err := exec.Command("docker", "cp", fmt.Sprintf("%s.tar.gz", chaincodeName), fmt.Sprintf("%s:/opt/gopath/src/github.com/hyperledger/fabric/peer", peer)).Output()
        if err != nil {
            return fmt.Errorf("复制链码包到 %s 失败: %v", peer, err)
        }

        // 安装链码
        fmt.Println(peer, "安装链码.....")
        cmd = exec.Command("docker", "exec", "-i", peer, "bash", "-c",
            fmt.Sprintf("peer lifecycle chaincode install /opt/gopath/src/github.com/hyperledger/fabric/peer/%s.tar.gz", chaincodeName))
        err = runCommand(cmd)
        if err != nil {
            return fmt.Errorf("链码在 %s 上安装失败: %v", peer, err)
        }
    }
    return nil
}



// 批准链码
func ApproveChaincode(channelID, chaincodeName, chaincodeLabel string, orgs []string) error {
    var packageID string

    // 查询链码的安装情况并获取 package-id
    fmt.Println("获取链码 package-id...")
    cmd := exec.Command("docker", "exec", "-i", "cli1", "bash", "-c",
        "peer lifecycle chaincode queryinstalled")
    output, err := cmd.Output()
    if err != nil {
        return fmt.Errorf("查询链码安装失败: %v", err)
    }

    // 解析查询输出，提取 package-id
    outputStr := string(output)
    fmt.Println("链码安装查询输出:", outputStr)
    
    // 假设格式为 "Package ID: yjwz_1:<package-id>, Label: yjwz_1"
    // 你可以根据输出格式来进行提取
    packageID, err = extractPackageID(outputStr, chaincodeName)
    if err != nil {
        return fmt.Errorf("未找到链码的 package-id: %v", err)
    }

    fmt.Println("链码 package-id:", packageID)

    // 为每个组织批准链码
    for _, org := range orgs {
        var cliContainer string

        // 根据组织名称选择正确的 CLI 容器
        switch org {
        case "Org1":
            cliContainer = "cli1"
        case "Org2":
            cliContainer = "cli2"
        case "Org3":
            cliContainer = "cli3"
        default:
            return fmt.Errorf("未知的组织: %s", org)
        }

        // 执行批准链码命令
        fmt.Println(org, "执行批准链码.....")
        cmd = exec.Command("docker", "exec", "-i", cliContainer, "bash", "-c",
            fmt.Sprintf("peer lifecycle chaincode approveformyorg --orderer orderer.example.com:7050 --channelID %s --name %s --version 1.0 --sequence 1 --init-required --package-id %s --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem", 
                channelID, chaincodeName, packageID))

        err := runCommand(cmd)
        if err != nil {
            return err
        }
    }
    return nil
}

// 提取 package-id 的辅助函数
func extractPackageID(output, chaincodeName string) (string, error) {
    // 在输出中查找 package-id，格式可能是 "Package ID: yjwz_1:<package-id>"
    var packageID string
    packageIDPattern := fmt.Sprintf(`Package ID: %s_1:([a-f0-9]+)`, chaincodeName)
    re := regexp.MustCompile(packageIDPattern)
    matches := re.FindStringSubmatch(output)
    if len(matches) < 2 {
        return "", fmt.Errorf("未找到链码 %s 的 package-id", chaincodeName)
    }
    packageID = fmt.Sprintf("%s_1:%s", chaincodeName, matches[1])
    return packageID, nil
}


// 提交链码
func CommitChaincode(channelID, chaincodeName string, peerAddresses []string, tlsRootCertFiles []string) error {
    if len(peerAddresses) != len(tlsRootCertFiles) {
        return fmt.Errorf("peerAddresses 和 tlsRootCertFiles 长度不匹配")
    }

    fmt.Println("提交链码.....")

    // 构建 peerAddresses 和 tlsRootCertFiles 参数
    peerArgs := ""
    for i := range peerAddresses {
        peerArgs += fmt.Sprintf("--peerAddresses %s --tlsRootCertFiles %s ", peerAddresses[i], tlsRootCertFiles[i])
    }

    // 执行链码提交命令
    cmd := exec.Command("docker", "exec", "-i", "cli1", "bash", "-c",
        fmt.Sprintf("peer lifecycle chaincode commit -o orderer.example.com:7050 --channelID %s --name %s --version 1.0 --sequence 1 --init-required --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem %s",
            channelID, chaincodeName, peerArgs))

    return runCommand(cmd)
}


// 执行命令行命令
func runCommand(cmd *exec.Cmd) error {
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    return cmd.Run()
}

