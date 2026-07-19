#include <stdint.h>
#include <stdlib.h>

#include <exception>
#include <string>
#include <vector>

#include <faiss/IndexFlat.h>

extern "C" {

struct OrbeliasFaissIndex {
  int dim;
  faiss::IndexFlatIP *index;
};

OrbeliasFaissIndex *orbelias_faiss_new(int dim) {
  if (dim <= 0) {
    return nullptr;
  }
  try {
    auto *h = new OrbeliasFaissIndex;
    h->dim = dim;
    h->index = new faiss::IndexFlatIP(dim);
    return h;
  } catch (...) {
    return nullptr;
  }
}

void orbelias_faiss_free(OrbeliasFaissIndex *h) {
  if (h == nullptr) {
    return;
  }
  delete h->index;
  delete h;
}

int orbelias_faiss_count(OrbeliasFaissIndex *h) {
  if (h == nullptr || h->index == nullptr) {
    return 0;
  }
  return static_cast<int>(h->index->ntotal);
}

int orbelias_faiss_add(OrbeliasFaissIndex *h, const float *vec) {
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

int orbelias_faiss_search(OrbeliasFaissIndex *h, const float *query, int k,
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
