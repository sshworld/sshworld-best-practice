import { notFound } from 'next/navigation'

async function fetchItem(id: string) {
  // 픽스처이므로 실제 조회 없음
  return id === 'missing' ? null : { id, name: 'Item ' + id }
}

export default async function ItemDetailPage({ params }: { params: { id: string } }) {
  const item = await fetchItem(params.id)
  if (!item) {
    // sink 후보: notFound() 를 던지지만 이 세그먼트(및 상위)에 not-found.tsx 가 없다.
    // 이 화면에서 대시보드로 돌아가는 링크도 없다.
    notFound()
  }
  return <div>{item.name}</div>
}
