import type Redis from 'ioredis';
import type { RedisOptions } from 'ioredis';
import type { SecretParam } from 'firebase-functions/params';

export declare const redisHostSecret: SecretParam;
export declare const redisPortSecret: SecretParam;
export declare const redisPasswordSecret: SecretParam;
export declare const REDIS_SECRETS: SecretParam[];

export declare function parseRedisEndpoint(
  rawHost: string,
  rawPort?: string | number
): { host: string; port: number };

export declare function findRedisCaCertificatePath(): string | null;
export declare function readRedisCaCertificate(): Buffer | null;

export declare function buildRedisOptions(overrides?: Record<string, any>): RedisOptions;
export declare function createRedisClient(customOptions?: Record<string, any>): Redis;

export declare function setRedisClientForTesting(client: Redis | null): void;
export declare function getRedisClient(options?: Record<string, any>): Redis;
export declare function closeRedis(): Promise<void>;

export declare const redis: Redis;

export default redis;
