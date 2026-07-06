#include <jni.h>

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "rochedb.h"

namespace {

jlong ptrToLong(void* p) {
  return static_cast<jlong>(reinterpret_cast<std::intptr_t>(p));
}

void* longToPtr(jlong h) {
  return reinterpret_cast<void*>(static_cast<std::intptr_t>(h));
}

roche_id makeId(jlong parent, jint epoch, jint seq, jdouble tWrite) {
  roche_id id{};
  id.parent = static_cast<std::uint64_t>(parent);
  id.epoch = static_cast<std::uint32_t>(epoch);
  id.seq = static_cast<std::uint32_t>(seq);
  id.t_write = static_cast<double>(tWrite);
  return id;
}

void throwRoche(JNIEnv* env, const char* fallback) {
  const char* message = roche_last_error();
  if (message == nullptr || message[0] == '\0') {
    message = fallback;
  }
  jclass cls = env->FindClass("org/rochedb/RocheDbException");
  if (cls != nullptr) {
    env->ThrowNew(cls, message);
  }
}

std::string toString(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) {
    return {};
  }
  std::string out(chars);
  env->ReleaseStringUTFChars(value, chars);
  return out;
}

jobject newId(JNIEnv* env, const roche_id& id) {
  jclass cls = env->FindClass("org/rochedb/RocheId");
  if (cls == nullptr) {
    return nullptr;
  }
  jmethodID ctor = env->GetMethodID(cls, "<init>", "(JIID)V");
  if (ctor == nullptr) {
    return nullptr;
  }
  return env->NewObject(cls, ctor, static_cast<jlong>(id.parent),
                        static_cast<jint>(id.epoch), static_cast<jint>(id.seq),
                        static_cast<jdouble>(id.t_write));
}

jbyteArray newByteArray(JNIEnv* env, const void* data, std::size_t len) {
  if (data == nullptr) {
    return nullptr;
  }
  jbyteArray out = env->NewByteArray(static_cast<jsize>(len));
  if (out == nullptr) {
    return nullptr;
  }
  if (len > 0) {
    env->SetByteArrayRegion(out, 0, static_cast<jsize>(len),
                            static_cast<const jbyte*>(data));
  }
  return out;
}

jstring newUtf8String(JNIEnv* env, const void* data, std::size_t len) {
  jbyteArray bytes = newByteArray(env, data, len);
  if (bytes == nullptr) {
    return nullptr;
  }
  jclass stringCls = env->FindClass("java/lang/String");
  jmethodID ctor = env->GetMethodID(stringCls, "<init>", "([BLjava/lang/String;)V");
  jstring charset = env->NewStringUTF("UTF-8");
  return static_cast<jstring>(env->NewObject(stringCls, ctor, bytes, charset));
}

std::vector<float> toFloats(JNIEnv* env, jfloatArray values) {
  std::vector<float> out;
  if (values == nullptr) {
    return out;
  }
  jsize len = env->GetArrayLength(values);
  out.resize(static_cast<std::size_t>(len));
  if (len > 0) {
    env->GetFloatArrayRegion(values, 0, len, out.data());
  }
  return out;
}

std::vector<std::uint8_t> toBytes(JNIEnv* env, jbyteArray values) {
  std::vector<std::uint8_t> out;
  if (values == nullptr) {
    return out;
  }
  jsize len = env->GetArrayLength(values);
  out.resize(static_cast<std::size_t>(len));
  if (len > 0) {
    env->GetByteArrayRegion(values, 0, len, reinterpret_cast<jbyte*>(out.data()));
  }
  return out;
}

jobject newHit(JNIEnv* env, const roche_hit& hit) {
  jclass cls = env->FindClass("org/rochedb/RocheHit");
  jmethodID ctor = env->GetMethodID(cls, "<init>", "(Lorg/rochedb/RocheId;D[B)V");
  jobject id = newId(env, hit.id);
  jbyteArray payload = newByteArray(env, hit.payload, hit.payload_len);
  return env->NewObject(cls, ctor, id, static_cast<jdouble>(hit.score), payload);
}

jobject newRetrieveResult(JNIEnv* env, const roche_retrieve_result* r) {
  jclass arrayListCls = env->FindClass("java/util/ArrayList");
  jmethodID listCtor = env->GetMethodID(arrayListCls, "<init>", "(I)V");
  jmethodID add = env->GetMethodID(arrayListCls, "add", "(Ljava/lang/Object;)Z");
  jobject hits = env->NewObject(arrayListCls, listCtor, static_cast<jint>(r->len));
  for (std::size_t i = 0; i < r->len; ++i) {
    jobject hit = newHit(env, r->hits[i]);
    env->CallBooleanMethod(hits, add, hit);
  }

  jclass cls = env->FindClass("org/rochedb/RocheRetrieveResult");
  jmethodID ctor =
      env->GetMethodID(cls, "<init>", "(Ljava/util/List;IIIIIIIID)V");
  return env->NewObject(cls, ctor, hits, static_cast<jint>(r->total_vectors),
                        static_cast<jint>(r->scanned),
                        static_cast<jint>(r->skipped_vectors),
                        static_cast<jint>(r->returned),
                        static_cast<jint>(r->rings_touched),
                        static_cast<jint>(r->payload_bytes),
                        static_cast<jint>(r->estimated_tokens),
                        static_cast<jint>(r->fanout_nodes),
                        static_cast<jdouble>(r->candidate_reduction));
}

}  // namespace

extern "C" {

JNIEXPORT jint JNICALL Java_org_rochedb_RocheNative_abiVersion(JNIEnv*, jclass) {
  return roche_abi_version();
}

JNIEXPORT jlong JNICALL Java_org_rochedb_RocheNative_open(JNIEnv* env, jclass,
                                                          jint nodes) {
  roche_init();
  void* db = roche_open(nodes);
  if (db == nullptr) {
    throwRoche(env, "failed to open RocheDB");
    return 0;
  }
  return ptrToLong(db);
}

JNIEXPORT jlong JNICALL Java_org_rochedb_RocheNative_openDir(JNIEnv* env, jclass,
                                                             jint nodes,
                                                             jstring dir) {
  roche_init();
  std::string d = toString(env, dir);
  void* db = roche_open_dir(nodes, d.c_str());
  if (db == nullptr) {
    throwRoche(env, "failed to open RocheDB directory");
    return 0;
  }
  return ptrToLong(db);
}

JNIEXPORT jlong JNICALL Java_org_rochedb_RocheNative_connect(JNIEnv* env, jclass,
                                                             jstring peers) {
  roche_init();
  std::string p = toString(env, peers);
  void* db = roche_connect(p.c_str());
  if (db == nullptr) {
    throwRoche(env, "failed to connect to RocheDB");
    return 0;
  }
  return ptrToLong(db);
}

JNIEXPORT jlong JNICALL Java_org_rochedb_RocheNative_connectAuth(
    JNIEnv* env, jclass, jstring peers, jstring username, jstring password,
    jstring authToken, jstring secretKey, jstring galaxy) {
  roche_init();
  std::string p = toString(env, peers);
  std::string u = toString(env, username);
  std::string pw = toString(env, password);
  std::string token = toString(env, authToken);
  std::string secret = toString(env, secretKey);
  std::string g = toString(env, galaxy);
  void* db = roche_connect_auth(p.c_str(), u.c_str(), pw.c_str(), token.c_str(),
                                secret.c_str(), g.c_str());
  if (db == nullptr) {
    throwRoche(env, "failed to connect to RocheDB with auth");
    return 0;
  }
  return ptrToLong(db);
}

JNIEXPORT void JNICALL Java_org_rochedb_RocheNative_close(JNIEnv*, jclass,
                                                          jlong handle) {
  roche_close(longToPtr(handle));
}

JNIEXPORT jdouble JNICALL Java_org_rochedb_RocheNative_now(JNIEnv*, jclass,
                                                           jlong handle) {
  return roche_now(longToPtr(handle));
}

JNIEXPORT void JNICALL Java_org_rochedb_RocheNative_advance(JNIEnv*, jclass,
                                                            jlong handle,
                                                            jdouble dt) {
  roche_advance(longToPtr(handle), dt);
}

JNIEXPORT void JNICALL Java_org_rochedb_RocheNative_configureRing(
    JNIEnv* env, jclass, jlong handle, jstring ring, jdouble period) {
  std::string r = toString(env, ring);
  if (roche_ring_configure(longToPtr(handle), r.c_str(), period) != ROCHE_OK) {
    throwRoche(env, "failed to configure ring");
  }
}

JNIEXPORT void JNICALL Java_org_rochedb_RocheNative_setGalaxyDescription(
    JNIEnv* env, jclass, jlong handle, jstring description) {
  std::string d = toString(env, description);
  if (roche_set_galaxy_description(longToPtr(handle), d.c_str()) != ROCHE_OK) {
    throwRoche(env, "failed to set galaxy description");
  }
}

JNIEXPORT void JNICALL Java_org_rochedb_RocheNative_setRingDescription(
    JNIEnv* env, jclass, jlong handle, jstring ring, jstring description) {
  std::string r = toString(env, ring);
  std::string d = toString(env, description);
  if (roche_set_ring_description(longToPtr(handle), r.c_str(), d.c_str()) !=
      ROCHE_OK) {
    throwRoche(env, "failed to set ring description");
  }
}

JNIEXPORT jobject JNICALL Java_org_rochedb_RocheNative_put(
    JNIEnv* env, jclass, jlong handle, jstring ring, jbyteArray payload) {
  std::string r = toString(env, ring);
  std::vector<std::uint8_t> bytes = toBytes(env, payload);
  roche_id id{};
  if (roche_put(longToPtr(handle), r.c_str(), bytes.data(), bytes.size(), &id) !=
      ROCHE_OK) {
    throwRoche(env, "put failed");
    return nullptr;
  }
  return newId(env, id);
}

JNIEXPORT jobject JNICALL Java_org_rochedb_RocheNative_putVec(
    JNIEnv* env, jclass, jlong handle, jstring ring, jbyteArray payload,
    jfloatArray vector) {
  std::string r = toString(env, ring);
  std::vector<std::uint8_t> bytes = toBytes(env, payload);
  std::vector<float> vec = toFloats(env, vector);
  roche_id id{};
  if (roche_put_vec(longToPtr(handle), r.c_str(), bytes.data(), bytes.size(),
                    vec.data(), vec.size(), &id) != ROCHE_OK) {
    throwRoche(env, "putVec failed");
    return nullptr;
  }
  return newId(env, id);
}

JNIEXPORT jbyteArray JNICALL Java_org_rochedb_RocheNative_get(
    JNIEnv* env, jclass, jlong handle, jlong parent, jint epoch, jint seq,
    jdouble tWrite) {
  roche_id id = makeId(parent, epoch, seq, tWrite);
  std::size_t len = 0;
  void* ptr = roche_get(longToPtr(handle), id, &len);
  if (ptr == nullptr) {
    return nullptr;
  }
  jbyteArray out = newByteArray(env, ptr, len);
  roche_free(ptr);
  return out;
}

JNIEXPORT jobjectArray JNICALL Java_org_rochedb_RocheNative_batchGet(
    JNIEnv* env, jclass, jlong handle, jlongArray parents, jintArray epochs,
    jintArray seqs, jdoubleArray tWrites) {
  jsize len = env->GetArrayLength(parents);
  std::vector<jlong> p(len);
  std::vector<jint> e(len);
  std::vector<jint> s(len);
  std::vector<jdouble> t(len);
  env->GetLongArrayRegion(parents, 0, len, p.data());
  env->GetIntArrayRegion(epochs, 0, len, e.data());
  env->GetIntArrayRegion(seqs, 0, len, s.data());
  env->GetDoubleArrayRegion(tWrites, 0, len, t.data());

  std::vector<roche_id> ids(static_cast<std::size_t>(len));
  for (jsize i = 0; i < len; ++i) {
    ids[static_cast<std::size_t>(i)] = makeId(p[i], e[i], s[i], t[i]);
  }

  roche_batch_result* result =
      roche_batch_get(longToPtr(handle), ids.data(), ids.size());
  if (result == nullptr) {
    throwRoche(env, "batchGet failed");
    return nullptr;
  }

  jclass byteArrayCls = env->FindClass("[B");
  jobjectArray out = env->NewObjectArray(static_cast<jsize>(result->len),
                                         byteArrayCls, nullptr);
  for (std::size_t i = 0; i < result->len; ++i) {
    const roche_value& value = result->values[i];
    if (value.data != nullptr) {
      env->SetObjectArrayElement(
          out, static_cast<jsize>(i), newByteArray(env, value.data, value.len));
    }
  }
  roche_batch_get_free(result);
  return out;
}

JNIEXPORT jbyteArray JNICALL Java_org_rochedb_RocheNative_query(
    JNIEnv* env, jclass, jlong handle, jlong parent, jint epoch, jint seq,
    jdouble tWrite, jstring selection) {
  roche_id id = makeId(parent, epoch, seq, tWrite);
  std::string s = toString(env, selection);
  std::size_t len = 0;
  void* ptr = roche_query(longToPtr(handle), id, s.c_str(), &len);
  if (ptr == nullptr) {
    return nullptr;
  }
  jbyteArray out = newByteArray(env, ptr, len);
  roche_free(ptr);
  return out;
}

JNIEXPORT jobject JNICALL Java_org_rochedb_RocheNative_retrieve(
    JNIEnv* env, jclass, jlong handle, jfloatArray vector, jstring ring,
    jint budget, jint topRings, jint focus) {
  std::vector<float> vec = toFloats(env, vector);
  std::string r = toString(env, ring);
  roche_retrieve_result* result =
      roche_retrieve(longToPtr(handle), vec.data(), vec.size(), r.c_str(),
                     budget, topRings, focus);
  if (result == nullptr) {
    throwRoche(env, "retrieve failed");
    return nullptr;
  }
  jobject out = newRetrieveResult(env, result);
  roche_retrieve_free(result);
  return out;
}

JNIEXPORT jstring JNICALL Java_org_rochedb_RocheNative_atlas(
    JNIEnv* env, jclass, jlong handle, jfloatArray queryVector,
    jint maxCentroidDims) {
  std::vector<float> vec = toFloats(env, queryVector);
  std::size_t len = 0;
  void* ptr = roche_atlas(longToPtr(handle), vec.data(), vec.size(),
                          maxCentroidDims, &len);
  if (ptr == nullptr) {
    throwRoche(env, "atlas failed");
    return nullptr;
  }
  jstring out = newUtf8String(env, ptr, len);
  roche_free(ptr);
  return out;
}

JNIEXPORT jint JNICALL Java_org_rochedb_RocheNative_locate(
    JNIEnv*, jclass, jlong handle, jlong parent, jint epoch, jint seq,
    jdouble tWrite, jdouble at) {
  return roche_locate(longToPtr(handle), makeId(parent, epoch, seq, tWrite), at);
}

JNIEXPORT jdouble JNICALL Java_org_rochedb_RocheNative_nextVisit(
    JNIEnv*, jclass, jlong handle, jlong parent, jint epoch, jint seq,
    jdouble tWrite, jint node) {
  return roche_next_visit(longToPtr(handle), makeId(parent, epoch, seq, tWrite),
                          node);
}

JNIEXPORT jdouble JNICALL Java_org_rochedb_RocheNative_nextJoin(
    JNIEnv*, jclass, jlong handle, jlong aParent, jint aEpoch, jint aSeq,
    jdouble aTWrite, jlong bParent, jint bEpoch, jint bSeq, jdouble bTWrite) {
  return roche_next_join(longToPtr(handle),
                         makeId(aParent, aEpoch, aSeq, aTWrite),
                         makeId(bParent, bEpoch, bSeq, bTWrite));
}

}  // extern "C"

