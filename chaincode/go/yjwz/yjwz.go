package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// YjwzContract 物资管理的合约
type YjwzContract struct {
	contractapi.Contract
}

// EnterRecord 物资入库记录
type EnterRecord struct {
	CreatedTime   string `json:"createdTime"`
	MaterialsName string `json:"materialsName"`
	MaterialNumber int    `json:"materialNumber"`
	Notess        string `json:"notess"`
}

// GetOutRecord 物资出库记录
type GetOutRecord struct {
	CreatedTime   string `json:"createdTime"`
	MaterialsName string `json:"materialsName"`
	MaterialNumber int    `json:"materialNumber"`
	Intention     string `json:"intention"`
	ParentHash    string `json:"parentHash"`
}

// InitLedger 初始化 Ledger
func (c *YjwzContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	fmt.Println("Initialize the ledger with some basic data.")
	return nil
}

// Enter 物资入库操作
func (c *YjwzContract) Enter(ctx contractapi.TransactionContextInterface, createdTime string, materialsName string, notess string, materialNumber string) (string, error) {
	materialNum, err := strconv.Atoi(materialNumber)
	if err != nil {
		return "", fmt.Errorf("materialNumber should be an integer: %v", err)
	}

	enterHashValue := c.GenerateHash(createdTime, materialsName, materialNumber, strconv.FormatInt(time.Now().Unix(), 10))

	enterRecord := EnterRecord{
		CreatedTime:   createdTime,
		MaterialsName: materialsName,
		MaterialNumber: materialNum,
		Notess:        notess,
	}

	enterRecordBytes, err := json.Marshal(enterRecord)
	if err != nil {
		return "", fmt.Errorf("failed to marshal enterRecord: %v", err)
	}

	err = ctx.GetStub().PutState(enterHashValue, enterRecordBytes)
	if err != nil {
		return "", fmt.Errorf("failed to put state: %v", err)
	}

	fmt.Printf("New Material: %s created at %s\n", enterRecord.MaterialsName, enterRecord.CreatedTime)
	return enterHashValue, nil
}

// GetOut 物资出库操作
func (c *YjwzContract) GetOut(ctx contractapi.TransactionContextInterface, createdTime string, materialsName string, materialNumber string, intention string, enterHashValue string) (string, error) {
	materialNum, err := strconv.Atoi(materialNumber)
	if err != nil {
		return "", fmt.Errorf("materialNumber should be an integer: %v", err)
	}

	getOutHashValue := c.GenerateHash(createdTime, materialsName, materialNumber, intention, enterHashValue)

	getOutRecord := GetOutRecord{
		CreatedTime:   createdTime,
		MaterialsName: materialsName,
		MaterialNumber: materialNum,
		Intention:     intention,
		ParentHash:    enterHashValue,
	}

	getOutRecordBytes, err := json.Marshal(getOutRecord)
	if err != nil {
		return "", fmt.Errorf("failed to marshal getOutRecord: %v", err)
	}

	err = ctx.GetStub().PutState(getOutHashValue, getOutRecordBytes)
	if err != nil {
		return "", fmt.Errorf("failed to put state: %v", err)
	}

	fmt.Printf("New Get Out: %s dispatched to %s\n", getOutRecord.MaterialsName, getOutRecord.Intention)
	return getOutHashValue, nil
}

// GetEnter 查询物资入库记录
func (c *YjwzContract) GetEnter(ctx contractapi.TransactionContextInterface, enterHashValue string) (*EnterRecord, error) {
	enterRecordBytes, err := ctx.GetStub().GetState(enterHashValue)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if enterRecordBytes == nil {
		return nil, fmt.Errorf("enter record with hash %s does not exist", enterHashValue)
	}

	var enterRecord EnterRecord
	err = json.Unmarshal(enterRecordBytes, &enterRecord)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal enterRecord: %v", err)
	}

	return &enterRecord, nil
}

// GetGetOut 查询物资出库记录
func (c *YjwzContract) GetGetOut(ctx contractapi.TransactionContextInterface, getOutHashValue string) (*GetOutRecord, error) {
	getOutRecordBytes, err := ctx.GetStub().GetState(getOutHashValue)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if getOutRecordBytes == nil {
		return nil, fmt.Errorf("get out record with hash %s does not exist", getOutHashValue)
	}

	var getOutRecord GetOutRecord
	err = json.Unmarshal(getOutRecordBytes, &getOutRecord)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal getOutRecord: %v", err)
	}

	return &getOutRecord, nil
}

// GenerateHash 生成 Hash 值
func (c *YjwzContract) GenerateHash(inputs ...string) string {
	hasher := sha256.New()
	for _, input := range inputs {
		hasher.Write([]byte(input))
	}
	return hex.EncodeToString(hasher.Sum(nil))
}

func main() {
	chaincode, err := contractapi.NewChaincode(new(YjwzContract))
	if err != nil {
		fmt.Printf("Error create YjwzContract chaincode: %v", err)
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting YjwzContract chaincode: %v", err)
	}
}

