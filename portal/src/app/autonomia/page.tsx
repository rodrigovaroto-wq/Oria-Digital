import { redirect } from "next/navigation";

// `/autonomia` virou a aba "Qualidade da automação" de `/administracao` (item 33 do
// redesenho). A rota antiga fica só para o link salvo, o favorito e a mensagem já
// enviada não caírem em 404. Redirecionamento temporário (307), não 308: o 308 o
// navegador guarda para sempre, e o endereço novo ainda pode mudar.
export default function AutonomiaAntiga() {
  redirect("/administracao");
}
