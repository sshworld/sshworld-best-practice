import Link from 'next/link'
import { redirect } from 'next/navigation'

type Item = { id: string; name: string }

async function createItem(formData: FormData) {
  'use server'
  const name = formData.get('name')
  await fakeSaveItem(name)
  // 미폐쇄 흐름: 성공 시 redirect 만 있고, 실패(fakeSaveItem 예외/검증 실패) 반환 경로가 없다.
  redirect('/dash/items')
}

async function fakeSaveItem(_name: FormDataEntryValue | null) {
  // 실제 저장 로직 (픽스처이므로 빌드 대상 아님)
}

export default function ItemsPage({ items }: { items: Item[] }) {
  return (
    <div>
      <form action={createItem}>
        <input name="name" />
        <button type="submit">Create</button>
      </form>
      <ul>
        {items.map((item) => (
          <li key={item.id}>
            <Link href={`/dash/items/${item.id}`}>{item.name}</Link>
          </li>
        ))}
      </ul>
    </div>
  )
}
