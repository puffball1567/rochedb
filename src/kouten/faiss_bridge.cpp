#include <stdint.h>
#include <stdlib.h>

#include <exception>
#include <string>
#include <vector>

#include <faiss/IndexFlat.h>

extern "C" {

struct KoutenFaissIndex {
  int dim;
  faiss::IndexFlatIP *index;
};

KoutenFaissIndex *kouten_faiss_new(int dim) {
  if (dim <= 0) {
    return nullptr;
  }
  try {
    auto *h = new KoutenFaissIndex;
    h->dim = dim;
    h->index = new faiss::IndexFlatIP(dim);
    return h;
  } catch (...) {
    return nullptr;
  }
}

void kouten_faiss_free(KoutenFaissIndex *h) {
  if (h == nullptr) {
    return;
  }
  delete h->index;
  delete h;
}

int kouten_faiss_count(KoutenFaissIndex *h) {
  if (h == nullptr || h->index == nullptr) {
    return 0;
  }
  return static_cast<int>(h->index->ntotal);
}

int kouten_faiss_add(KoutenFaissIndex *h, const float *vec) {
  if (h == nullptr || h->index == nullptr || vec == nullptr) {
    return 0;
  }
  try {
    h->index->add(1, vec);
    return 1;
  } catch (...) {
    return 0;
  }
}

int kouten_faiss_search(KoutenFaissIndex *h, const float *query, int k,
                       int64_t *labels, float *scores) {
  if (h == nullptr || h->index == nullptr || query == nullptr ||
      labels == nullptr || scores == nullptr || k <= 0) {
    return 0;
  }
  try {
    h->index->search(1, query, k, scores, labels);
    return 1;
  } catch (...) {
    return 0;
  }
}

}  // extern "C"
