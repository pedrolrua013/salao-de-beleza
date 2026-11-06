import Link from "next/link";
import { exigirMembro } from "@/lib/auth";

export const metadata = { title: "Ajuda" };

type Topico = { t: string; passos?: string[]; texto?: string };
type Grupo = { titulo: string; itens: Topico[]; so?: "admin" };

const GRUPOS: Grupo[] = [
  {
    titulo: "No dia a dia",
    itens: [
      { t: "Como marcar um horário", passos: ["Abra a Agenda e escolha o dia.", "Em Novo agendamento, escolha cliente, serviço e profissional.", "Toque em um dos horários livres que aparecem e salve."] },
      { t: "Encaixar uma cliente na pausa da química", texto: "Na Agenda, a pausa aparece listrada: a química está agindo e o profissional está livre. Ao marcar, os horários que caem numa pausa aparecem listrados em verde. Para isso funcionar, cadastre a pausa do serviço em Catálogos." },
      { t: "A cliente queria um horário que está cheio", texto: "Na Agenda, em Lista de espera, coloque a cliente com o serviço, os dias e o período. Se alguém cancelar um horário que combina, ela recebe o aviso pelo WhatsApp com o link para marcar." },
      { t: "Bloquear folga, férias ou um compromisso", passos: ["Abra a Agenda e vá até Bloquear horário.", "Escolha o profissional, o início, o fim e, se quiser, o motivo.", "Para desbloquear, toque no × do bloqueio na agenda em colunas."] },
      { t: "Como cadastrar um cliente", passos: ["Abra Clientes e clique em Novo cliente.", "Preencha nome e telefone.", "Marque a caixa do WhatsApp só se o cliente aceitou receber mensagens."] },
      { t: "O cliente remarcou ou desistiu", texto: "No horário, abra o menu de mais ações e escolha Cancelar horário. O horário volta a ficar livre. Depois é só marcar de novo." },
      { t: "O cliente não apareceu", texto: "No horário, abra o menu de mais ações e escolha Marcar falta." },
      { t: "Quem ainda não confirmou?", texto: "Na tela Hoje, o cartão Ainda sem confirmação lista os clientes de hoje e de amanhã, com botão para ligar." },
    ],
  },
  {
    titulo: "Caixa e comanda",
    itens: [
      { t: "Como fechar a conta de uma cliente", passos: ["Na Agenda, toque em Iniciar e depois em Fechar na comanda (ou abra Caixa > Nova comanda).", "Confira os serviços, adicione produtos vendidos e a gorjeta, se houver.", "Registre o pagamento (dá para dividir em Pix, cartão e dinheiro) e toque em Fechar comanda."] },
      { t: "Abrir e fechar o caixa do dia", passos: ["Em Caixa, informe o troco que está na gaveta e toque em Abrir caixa.", "Retiradas e vales aos profissionais ficam em Retirada, vale ou entrada de troco.", "No fim do dia, abra Fechar o caixa, conte o que entrou em cada forma de pagamento e confirme. O sistema mostra se faltou ou sobrou dinheiro."] },
      { t: "A cliente pagou o sinal pelo link", texto: "O sinal aparece no horário da agenda. Quando você abre a comanda, ele já entra como pagamento, uma vez só." },
      { t: "Fechei a comanda errada", texto: "O administrador pode reabrir a comanda enquanto o caixa do dia estiver aberto, desde que a comissão dela ainda não tenha sido paga." },
    ],
  },
  {
    titulo: "Comissão e extrato",
    itens: [
      { t: "Quanto vou receber?", texto: "Em Meu extrato aparece, linha a linha, cada serviço e venda: o valor, o que foi descontado (taxa do cartão ou produto, se o salão usa), o percentual e quanto é seu. Os vales já aparecem descontados." },
      { t: "Pedi um vale", texto: "A recepção ou o administrador lança o vale, inclusive tirando o dinheiro do caixa. Ele é descontado no próximo pagamento e aparece no seu extrato." },
    ],
  },
  {
    titulo: "Ficha da cliente",
    itens: [
      { t: "Registrar a fórmula da cor", passos: ["Abra a cliente e vá em Ficha técnica > Nova ficha técnica.", "Preencha o serviço, a técnica, a pausa e as linhas da fórmula (zona, produto/tom, gramas e oxidante).", "Na próxima vez, toque em Repetir esta fórmula: tudo vem preenchido."] },
      { t: "Teste de alergia e de mecha", texto: "Registre cada teste na ficha da cliente. Ele fica com data e não pode ser alterado nem apagado: é a prova de que o salão fez o teste." },
      { t: "A mesma cliente está cadastrada duas vezes", texto: "Abra o cadastro que vai ficar e, no fim da página, use Unir cadastros duplicados. Horários, comandas, fichas e fotos do outro cadastro passam para este." },
    ],
  },
  {
    titulo: "WhatsApp e lembretes",
    itens: [
      { t: "Como o cliente confirma o horário", texto: "Ele recebe uma mensagem na véspera e outra 3 horas antes, e responde com um toque: Confirmo, Preciso remarcar ou Cancelar horário. A agenda se atualiza sozinha." },
      { t: "Quero falar com o cliente no lugar do robô", passos: ["Abra Conversas e escolha a conversa.", "Clique em Assumir. O robô para de responder.", "Quando terminar, clique em Devolver ao robô."] },
      { t: "O cliente não recebeu o lembrete", texto: "Confira se ele tem telefone e consentimento no cadastro, se os lembretes estão ligados em Salão e se o WhatsApp está conectado. Quem escreveu PARAR não recebe mais lembretes." },
    ],
  },
  {
    titulo: "Configurações do salão",
    so: "admin",
    itens: [
      { t: "Convidar ou desativar alguém da equipe", texto: "Em Salão, abra Equipe. Para convidar, informe nome, e-mail e papel. Para tirar o acesso, clique em Desativar; nenhum dado é apagado e dá para reativar depois." },
      { t: "Mudar horários e lembretes", texto: "Em Salão, ajuste abertura, fechamento, mensagem de boas-vindas e o horário do lembrete da véspera." },
      { t: "Mudar serviços, tempos e pausas", texto: "Em Catálogos, toque em Editar serviço. Informe o trabalho, a pausa (tempo em que o produto age) e a finalização. Horários já marcados continuam com os tempos antigos." },
      { t: "Dias de trabalho e almoço de cada profissional", texto: "Em Equipe, toque em Jornada. Marque os dias, a entrada, a saída e o almoço. O robô do WhatsApp e os horários sugeridos respeitam essa jornada." },
      { t: "Link de agendamento para o Instagram", texto: "Em Salão > Agendamento online está o link do salão. Cole na bio do Instagram, no Google e no status do WhatsApp. A cliente marca sem app e sem senha e recebe um link para ver e cancelar o horário." },
      { t: "Cobrar sinal para garantir o horário", passos: ["Em Salão > Agendamento online, cadastre a chave Pix e a política de cancelamento.", "Em Catálogos, edite o serviço e informe o Sinal online (%).", "Quando a cliente pagar, toque em Pix caiu: confirmar no horário da agenda. Com o Mercado Pago ligado, a confirmação é automática."] },
      { t: "Comissões e salão-parceiro", texto: "Em Comissões, defina o percentual padrão e as exceções, as taxas de cartão e o vínculo de cada profissional. No fim do período, registre o pagamento. O Relatório Salão Parceiro mostra a cota de cada lado para o contador." },
      { t: "Convite automático de retorno", texto: "Em Catálogos, informe em quantos dias cada serviço costuma ser refeito. Em Salão, ligue o convite automático: quem passar do prazo sem marcar recebe um convite com o link, no máximo um por mês." },
      { t: "Controlar o estoque", passos: ["Em Catálogos, cadastre os produtos: revenda com preço; uso interno (tinta, oxidante) em gramas ou ml, com o conteúdo da embalagem.", "Em Estoque, dê entrada quando a mercadoria chegar e informe quanto cada serviço consome.", "Quando a comanda fecha, a venda e o consumo saem sozinhos. Faça a contagem de vez em quando para acertar o saldo."] },
      { t: "Vender e usar pacotes", passos: ["Em Catálogos > Pacotes e clube, crie o pacote (ex.: 10 escovas por R$ 400).", "Na comanda da cliente, use Vender pacote ou clube e feche a comanda: o saldo de sessões aparece na ficha dela.", "Nas próximas visitas, a comanda mostra o botão Usar o pacote."] },
      { t: "Cashback", texto: "Em Salão > Trazer a cliente de volta, defina o percentual e a validade. O crédito nasce quando a comanda fecha e aparece como botão Usar o cashback na próxima comanda da cliente." },
      { t: "Vender e usar vale-presente", passos: ["Na comanda de quem está comprando, use Vender vale-presente: valor, para quem e uma mensagem.", "Ao fechar a comanda nasce o código. Em Caixa > Vales-presente, toque em Imprimir para entregar ou salvar em PDF.", "Quem ganhou informa o código na comanda dela, em Pagar com vale-presente. O saldo que sobrar vale para a próxima visita."] },
      { t: "Avaliação depois do atendimento", texto: "Em Salão, ligue o pedido de avaliação e cole o link de avaliação do Google. No dia seguinte ao atendimento a cliente recebe a pergunta de 0 a 10. As notas baixas aparecem no Painel para você falar com ela." },
      { t: "Ver como o salão está indo", texto: "O Painel mostra faturamento, ticket médio, ocupação da agenda, faltas, quem voltou e quem saiu com o retorno marcado, comparando com o período anterior." },
      { t: "Trazer clientes de outro sistema ou planilha", texto: "Em Salão > Importar e exportar, envie o CSV com nome e celular. No mesmo lugar dá para baixar todos os dados do salão quando quiser." },
      { t: "Conectar o WhatsApp", texto: "Em Salão, abra WhatsApp, preencha os dados do número e cadastre o webhook na Meta. A mesma tela mostra os três modelos de mensagem que a Meta precisa aprovar." },
    ],
  },
];

export default async function Ajuda() {
  const { membro } = await exigirMembro();
  const grupos = GRUPOS.filter((g) => !g.so || membro.papel === "admin");
  return (
    <div className="stack-lg">
      <div><h1>Ajuda</h1><p className="sec">Respostas curtas para o que mais se pergunta. Toque em uma pergunta para abrir.</p></div>
      {grupos.map((g) => (
        <section className="aj-grupo" key={g.titulo} aria-label={g.titulo}>
          <h2>{g.titulo}</h2>
          {g.itens.map((i) => (
            <details className="aj" key={i.t}>
              <summary>{i.t}</summary>
              <div className="aj-corpo">
                {i.texto && <p>{i.texto}</p>}
                {i.passos && <ol>{i.passos.map((p) => <li key={p}>{p}</li>)}</ol>}
              </div>
            </details>
          ))}
        </section>
      ))}
      <p className="sm sec">Não achou? Fale com o suporte. <Link href="/hoje">Voltar para Hoje</Link></p>
    </div>
  );
}
