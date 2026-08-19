'use client'
import { useRouter } from 'next/navigation'

// inbound 는 middleware.ts 의 redirect('/login') 이 준다.
export default function LoginPage() {
  const router = useRouter()

  function onSubmit() {
    // 로그인 성공 시 대시보드로 이동 — outbound 있음, sink 아님.
    router.push('/dash')
  }

  return <form onSubmit={onSubmit}>{/* login form */}</form>
}
