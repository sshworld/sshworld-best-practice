export type NavLink = { href: string; label: string }

// 사이드바/헤더가 공통으로 참조하는 네비게이션 링크 상수.
// 컴포넌트에서 <Link href="..."> 로 하드코딩하지 않고 이 배열을 순회한다.
export const NAV_LINKS: NavLink[] = [
  { href: '/dash', label: 'Dashboard' },
  { href: '/dash/items', label: 'Items' },
  { href: '/settings', label: 'Settings' },
]
