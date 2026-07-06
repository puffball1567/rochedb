/// <reference types="node" />

export class RocheError extends Error {}

export class RocheId {
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

  static parse(text: string): RocheId;
  toString(): string;
}

export interface RocheClientOptions {
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

export class RocheClient {
  readonly peers: Array<{ host: string; port: number }>;
  readonly timeoutMs: number;

  constructor(peers: string | string[], options?: RocheClientOptions);
  static connect(peers: string | string[], options?: RocheClientOptions): RocheClient;

  close(): Promise<void>;
  put(ring: string, payload: Buffer | string, options?: PutOptions): Promise<RocheId>;
  get(id: RocheId, options?: ReadOptions): Promise<Buffer | null>;
  query(id: RocheId, selection: string, options?: ReadOptions): Promise<Buffer | null>;
  health(node?: number): Promise<string>;
}
