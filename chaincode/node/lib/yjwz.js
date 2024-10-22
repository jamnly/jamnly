'use strict';

const { Contract } = require('fabric-contract-api');

class YjwzContract extends Contract {

    // 初始化 Ledger
    async InitLedger(ctx) {
        console.info('Initialize the ledger with some basic data.');
    }

    // 物资入库操作
    async enter(ctx, createdTime, materialsName, notess, materialNumber) {
        const enterHashValue = this.generateHash(createdTime, materialsName, materialNumber, Date.now().toString());
        
        const enterRecord = {
            createdTime,
            materialsName,
            materialNumber: parseInt(materialNumber),
            notess
        };

        await ctx.stub.putState(enterHashValue, Buffer.from(JSON.stringify(enterRecord)));

        console.info(`New Donation: ${enterRecord.materialsName} created at ${enterRecord.createdTime}.`);
        return enterHashValue;
    }

    // 物资出库操作
    async getOut(ctx, createdTime, materialsName, materialNumber, intention, enterHashValue) {
        const getOutHashValue = this.generateHash(createdTime, materialsName, materialNumber, intention, enterHashValue);

        const getOutRecord = {
            createdTime,
            materialsName,
            materialNumber: parseInt(materialNumber),
            intention,
            parentHash: enterHashValue
        };

        await ctx.stub.putState(getOutHashValue, Buffer.from(JSON.stringify(getOutRecord)));

        console.info(`New Get Out: ${getOutRecord.materialsName} dispatched to ${getOutRecord.intention}.`);
        return getOutHashValue;
    }

    // 查询物资入库记录
    async getEnter(ctx, enterHashValue) {
        const enterRecordBytes = await ctx.stub.getState(enterHashValue);
        if (!enterRecordBytes || enterRecordBytes.length === 0) {
            throw new Error(`Enter record with hash ${enterHashValue} does not exist`);
        }
        return JSON.parse(enterRecordBytes.toString());
    }

    // 查询物资出库记录
    async getGetOut(ctx, getOutHashValue) {
        const getOutRecordBytes = await ctx.stub.getState(getOutHashValue);
        if (!getOutRecordBytes || getOutRecordBytes.length === 0) {
            throw new Error(`Get Out record with hash ${getOutHashValue} does not exist`);
        }
        return JSON.parse(getOutRecordBytes.toString());
    }

    // 生成 Hash 值
    generateHash(...inputs) {
        const crypto = require('crypto');
        return crypto.createHash('sha256').update(inputs.join('')).digest('hex');
    }
}

module.exports = YjwzContract;

