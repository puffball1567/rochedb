#include <stdint.h>
#include <stdlib.h>

#include <exception>
#include <string>
#include <vector>

#include <faiss/IndexFlat.h>

extern "C" {

struct RocheFaissIndex {
  int dim;
  faiss::IndexFlatIP *index;
};

RocheFaissIndex *roche_faiss_new(int dim) {
  if (dim <= 0) {
    return nullptr;
  }
  try {
    auto *h = new RocheFaissIndex;
    h->dim = dim;
    h->index = new faiss::IndexFlatIP(dim);
    return h;
  } catch (...) {
    return nullptr;
  }
}

void roche_faiss_free(RocheFaissIndex *h) {
  if (h == nullptr) {
    return;
  }
  delete h->index;
  delete h;
}

int roche_faiss_count(RocheFaissIndex *h) {
  if (h == nullptr || h->index == nullptr) {
    return 0;
  }
  return static_cast<int>(h->index->ntotal);
}

int roche_faiss_add(RocheFaissIndex *h, const float *vec) {
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

int roche_faiss_search(RocheFaissIndex *h, const float *query, int k,
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
