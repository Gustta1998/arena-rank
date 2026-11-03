# Arena Rank Gusta

Site oficial do ranking de eFootball, conectado ao Supabase.

## Prime Cup — integração em preparação

A branch `feature/prime-cup-integracao` adiciona a aba **Prime Cup** no menu sem alterar dados, regras de pontuação ou o histórico do ranking.

A aba carrega uma **prévia experimental** em iframe de `https://joyful-daifuku-216de4.netlify.app/` ao informar um UUID de evento. A página externa é temporária e **não é a publicação definitiva da apresentação**.

### Antes de mesclar no site oficial

1. Hospedar os arquivos aprovados de apresentação (HTML, vídeo inicial, música, vídeo final e escudos) sob um endereço estável e sob controle do projeto; remover a dependência do Netlify experimental.
2. Integrar o painel Admin e as funções do Supabase sem expor permissões ou resultados não revelados.
3. Verificar o fluxo completo — abertura, vídeo, logo Prime Cup, envelopes, revelações, tabela e encerramento — em desktop e iPhone.
4. Validar os ensaios com os mesmos estados e permissões de acesso usados na publicação.
5. Revisar a implantação Vercel e mesclar somente após aprovação.

O `index.html` do ranking continua a página principal; a aba da Prime Cup é independente.
