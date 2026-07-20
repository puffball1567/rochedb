/// <reference types="node" />

export class KoutenError extends Error {}

export class KoutenId {
  readonly parent: bigint;
  readonly epoch: number;
  readonly seq: number;
  readonly tWrite: number;
  readonly period: number;
  readonly head: number;

  constructor(
    parent: bigint | number | string,
    epoch: number | string,
    seq: number | string,
    tWrite: number | string,
    period: number | string,
    head: number | string,
  );

  static parse(text: string): KoutenId;
  toString(): string;
}

export interface KoutenClientOptions {
  timeout?: number;
  timeoutMs?: number;
}

export interface PutOptions {
  vector?: number[];
  node?: number;
}

export interface ReadOptions {
  node?: number;
}

export class KoutenClient {
  readonly peers: Array<{ host: string; port: number }>;
  readonly timeoutMs: number;

  constructor(peers: string | string[], options?: KoutenClientOptions);
  static connect(peers: string | string[], options?: KoutenClientOptions): KoutenClient;

  close(): Promise<void>;
  put(ring: string, payload: Buffer | string, options?: PutOptions): Promise<KoutenId>;
  get(id: KoutenId, options?: ReadOptions): Promise<Buffer | null>;
  query(id: KoutenId, selection: string, options?: ReadOptions): Promise<Buffer | null>;
  health(node?: number): Promise<string>;
}
