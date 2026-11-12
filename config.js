// 기류 사이트 설정 파일
// Supabase 프로젝트의 Project Settings → API 에서 값을 복사해 넣어주세요.
// - url: Project URL
// - anonKey: anon public(publishable) 키. 공개돼도 안전하게 설계된 키예요.
// ※ service_role(secret) 키는 절대 여기에 넣지 마세요.
// url 또는 anonKey가 비어 있으면 로그인·회원가입·후기 쓰기 기능은 자동으로 꺼져요.
window.GIRYU_CFG = {
  url: '',
  anonKey: '',
  kakao: false   // 카카오 로그인을 Supabase에서 켠 뒤 true로 바꾸면 버튼이 나타나요
};
