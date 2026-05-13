// 순수 타입 + 번역 데이터. server / client 양쪽에서 import 가능.
// cookie 읽기는 서버 전용이라 i18n-server.ts 로 분리.

export type Locale = "ko" | "en";

export const LOCALE_COOKIE = "locale";

export const translations = {
  ko: {
    nav: {
      datasets: "데이터셋",
      library: "라이브러리",
      pricing: "가격",
      version: "버전",
    },
    topSearch: {
      placeholder: "데이터셋, 모달리티, 종(species)…",
      submit: "검색",
    },
    landing: {
      kicker: "정밀한 연구를 위한 공공 데이터셋 검색",
      title: "연구 설계에 맞는 데이터셋을 빠르게 찾아드립니다.",
      subtitle:
        "NCBI, EBI, HCA, GDC 의 공공 메타데이터를 의미 검색과 키워드 검색으로 동시에 살펴봅니다. 결과마다 점수 산출 근거를 함께 보여드려 블랙박스 없이 비교할 수 있습니다.",
      heroPlaceholder:
        "찾고 있는 데이터를 자유롭게 적어 주세요. 예: 인간 췌장 섬세포 단일세포 RNA-seq",
      heroSubmit: "검색 →",
      tryLabel: "예시:",
      suggestions: [
        "인간 PBMC 단일세포 RNA-seq",
        "히스톤 크로마틴 리모델링",
        "종양 면역 미세환경",
        "박테리아 전장 유전체 시퀀싱",
        "섬유아세포 H3K4me3",
      ],
      featuresHeading: "Geno Finder 의 강점",
      features: [
        {
          heading: "하이브리드 검색",
          body: "의미 기반(Dense embedding) 검색과 키워드 기반(BM25) 검색을 결합해 정확도를 높였습니다. 결과마다 두 점수를 모두 확인할 수 있습니다.",
        },
        {
          heading: "모달리티 자동 분류",
          body: "로컬 LLM(Phi-4 mini)이 모든 데이터셋을 표준 어휘(scRNA-seq, ChIP-seq, WGS 등)로 자동 분류해 정확한 필터링을 지원합니다.",
        },
        {
          heading: "프라이버시 우선",
          body: "외부 API 호출 없이 로컬 LLM 만 사용합니다. 저장된 검색어는 사용자별 키로 암호화하고, 데이터베이스 차원에서 다른 사용자의 데이터를 차단합니다.",
        },
      ],
    },
    search: {
      titlePrefix: "검색 결과",
      titleEmpty: "검색을 시작해 보세요",
      summaryCandidates: "건의 후보 데이터셋",
      summaryFilteredOf: "건 (필터 적용, 전체 ",
      summaryFilteredOfSuffix: "건 중)",
      placeholderHelp:
        "위 검색창에 찾고 있는 데이터를 자유롭게 입력해 보세요. 예: \"인간 PBMC 면역반응 단일세포\", \"H3K4me3 ChIP-seq\", \"박테리아 게놈 시퀀싱\".",
      errorTitle: "검색에 실패했습니다",
      errorHint:
        "API 서버가 실행 중인지 확인해 주세요. 예: cd apps/api && uv run uvicorn src.main:app",
      noResults: "조건에 맞는 결과가 없습니다.",
      noResultsHint: "필터를 줄이거나 검색어를 더 폭넓게 입력해 보세요.",
    },
    filters: {
      heading: "필터",
      clearAll: "모두 해제",
      modality: "모달리티",
      sourceDb: "출처 DB",
      access: "접근 권한",
      dataAvailability: "데이터 가용성",
      accessAny: "전체 (제한 데이터 포함)",
      accessOpen: "공개 데이터만",
      hasProcessed: "가공 데이터 있음",
    },
    result: {
      noTitle: "(제목 없음)",
      processed: "✓ processed",
      sourceLink: "출처 ↗",
      semantic: "Semantic",
      lexical: "Lexical",
      rrf: "RRF",
    },
    datasetDetail: {
      back: "← 검색으로 돌아가기",
      notFound: "데이터셋",
      notFoundSuffix: ", 현재 검색 가능한 목록에 없습니다.",
      notFoundHint:
        "지금은 최근에 수집된 데이터셋만 포함하고 있습니다. 추가 수집이 필요합니다.",
      loadFail: "불러오기에 실패했습니다",
      submitted: "제출일",
      abstract: "초록",
      whyMatch: "매칭 근거",
      modality: "모달리티",
      organism: "종(species)",
      libraryStrategy: "라이브러리 전략",
      platform: "플랫폼",
      access: "접근 권한",
      hasProcessed: "가공 데이터",
      nSamples: "샘플 수",
      yes: "있음",
      no: "없음",
      none: "—",
      openIn: "열기",
    },
    footer: {
      tagline: "공공 데이터셋 검색 ·",
      securityTxt: "security.txt",
      apiDocs: "API 문서",
      terms: "이용약관",
      comingSoon: "준비 중",
    },
    languageToggle: {
      switchTo: "EN",
      ariaLabel: "Switch to English",
    },
  },
  en: {
    nav: {
      datasets: "Datasets",
      library: "Library",
      pricing: "Pricing",
      version: "version",
    },
    topSearch: {
      placeholder: "Search datasets, modality, organism…",
      submit: "Search",
    },
    landing: {
      kicker: "Public dataset discovery for the rigorous researcher",
      title: "Find the right dataset for your research design, fast.",
      subtitle:
        "Semantic + lexical hybrid search over NCBI, EBI, HCA, GDC. Score breakdown shown for every result. Never a black box.",
      heroPlaceholder:
        "Describe your research design. E.g., single-cell RNA-seq of human pancreatic islets",
      heroSubmit: "Search →",
      tryLabel: "Try:",
      suggestions: [
        "single-cell RNA-seq human PBMC",
        "histone chromatin remodeling",
        "tumor immune microenvironment",
        "bacterial whole genome sequencing",
        "fibroblast H3K4me3",
      ],
      featuresHeading: "Why Geno Finder?",
      features: [
        {
          heading: "Hybrid retrieval",
          body: "Dense embeddings (Qdrant) + BM25 (OpenSearch) → reciprocal rank fusion. Both signals exposed per result.",
        },
        {
          heading: "Modality classification",
          body: "Local Phi-4 mini classifies every dataset into a controlled vocabulary (scRNA-seq, ChIP-seq, WGS, …). Filter precisely.",
        },
        {
          heading: "Privacy first",
          body: "Local LLM only. Saved queries are envelope-encrypted with per-tenant DEK. Cross-tenant access blocked at the database.",
        },
      ],
    },
    search: {
      titlePrefix: "Results for",
      titleEmpty: "Start searching",
      summaryCandidates: "candidate datasets",
      summaryFilteredOf: "of ",
      summaryFilteredOfSuffix: " (filtered)",
      placeholderHelp:
        "Enter a research design query above. Examples: \"single-cell PBMC immune response\", \"histone H3K4me3 ChIP-seq\", \"bacterial genome sequencing\".",
      errorTitle: "Search failed",
      errorHint:
        "Verify the API server is running. e.g., cd apps/api && uv run uvicorn src.main:app",
      noResults: "No results matched.",
      noResultsHint: "Try removing a filter or broadening the query.",
    },
    filters: {
      heading: "Filters",
      clearAll: "Clear all",
      modality: "Modality",
      sourceDb: "Source DB",
      access: "Access",
      dataAvailability: "Data availability",
      accessAny: "Any (incl. controlled)",
      accessOpen: "Open access only",
      hasProcessed: "Has processed data",
    },
    result: {
      noTitle: "(no title)",
      processed: "✓ processed",
      sourceLink: "Source ↗",
      semantic: "Semantic",
      lexical: "Lexical",
      rrf: "RRF",
    },
    datasetDetail: {
      back: "← Back to search",
      notFound: "Dataset",
      notFoundSuffix: "not found in the indexed corpus.",
      notFoundHint:
        "The corpus currently holds the most recent ingested datasets only. Run another harvest pass to expand it.",
      loadFail: "Failed to load",
      submitted: "submitted",
      abstract: "Abstract",
      whyMatch: "Why this match",
      modality: "Modality",
      organism: "Organism",
      libraryStrategy: "Library strategy",
      platform: "Platform",
      access: "Access",
      hasProcessed: "Has processed data",
      nSamples: "n samples",
      yes: "yes",
      no: "no",
      none: "—",
      openIn: "Open in",
    },
    footer: {
      tagline: "Public dataset discovery from",
      securityTxt: "security.txt",
      apiDocs: "API docs",
      terms: "Terms",
      comingSoon: "coming soon",
    },
    languageToggle: {
      switchTo: "한",
      ariaLabel: "한국어로 전환",
    },
  },
} as const;

export type T = (typeof translations)["ko"];
