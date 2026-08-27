# frozen_string_literal: true

module Renegotiations
  # S9 / BE-225, BE-226, BE-229, OPS-192, OPS-194 — **anexos da renegociação**.
  #
  # Este serviço é a resposta ao **D-82**, que são cinco defeitos de segurança no
  # mesmo recurso. O que ele garante, e o que cada garantia substitui:
  #
  # | Garantia | O que havia no legado |
  # | --- | --- |
  # | Limites **no servidor** (4 arquivos, 5 MB), lidos do catálogo | Os dois números só existiam no JavaScript, lendo `.lesson_attachment_content_wrapper` — seletor **de outro produto** — e comparando com `NaN` (D-50). O servidor aceitava qualquer coisa |
  # | Tipo conferido pelos **magic bytes**, contra allowlist | `do_not_validate_attachment_file_type` **e** o detector de spoof monkey-patchado para `false` |
  # | Binário em armazenamento **privado**, alcançável só por URL assinada de prazo curto | Arquivo em `public/system/:attachment/:id/…`, servido como estático, URL adivinhável, **sem autenticação** |
  # | `#destroy` **só pelo autor**, checado aqui | A regra de dono era **só visual** |
  # | Contador coerente | `attachments_count` nascia NULL e `nil > 0` derrubava o detalhe |
  #
  # **O teto de 4 é contado em linhas irmãs**, não pelo motor: cada
  # `RenegotiationAttachment` tem UM binário (é a linha que carrega título e
  # autor). O número vem de `config/attachments.yml`, e é o mesmo que a tela lê em
  # `GET /api/v1/attachments/limits` — nem o servidor nem a tela têm "4" escrito.
  class AttachmentService
    class << self
      include Result

      def spec
        Sfg::Attachments.spec_for('renegotiation_attachment', 'file')
      end

      def max_files = spec.max_files

      # Anexa N arquivos a uma renegociação. **Ou todos entram, ou nenhum entra** —
      # o legado criava um registro por arquivo num laço, acumulava os erros num
      # `ActiveModel::Errors` avulso e respondia 422 **com metade dos arquivos já
      # gravados**.
      def attach!(renegotiation:, files:, actor:)
        arquivos = Array(files).compact
        return unprocessable('Nenhum arquivo enviado.') if arquivos.empty?

        ja_anexados = renegotiation.attachments.count
        if ja_anexados + arquivos.size > max_files
          # O teto é conferido contra o ESTADO, não contra o lote: sem isso, quatro
          # requisições de um arquivo cada passam e a renegociação termina com oito.
          return unprocessable(
            "O máximo de arquivos permitido para envio é de #{max_files} arquivos"
          )
        end

        criados = []
        RenegotiationAttachment.transaction do
          arquivos.each do |arquivo|
            anexo = RenegotiationAttachment.new(renegotiation: renegotiation,
                                                project_id: renegotiation.project_id,
                                                user_id: actor&.id)
            anexo.file.attach(payload_for(arquivo))
            anexo.save!
            criados << anexo
          end
          renegotiation.reload
        end

        created({ attachments: criados })
      rescue ActiveRecord::RecordInvalid => e
        from_record_invalid(e)
      end

      # **Renomear o anexo — DEC-53.** No legado isto nunca funcionou para
      # ninguém: `pub/renegotiation_attachments_controller.rb:51` chamava
      # `update_attributes(renegotiation_params)` com **dois** erros na mesma
      # linha — o método `renegotiation_params` não existe naquele controller (só
      # `renegotiation_attachment_params`) e `update_attributes` foi removido no
      # Rails 6.1 —, e o `respond_to` inteiro estava comentado. `NameError`
      # garantido, sem resposta nenhuma. Nasce funcionando aqui.
      def rename!(attachment:, title:)
        novo = title.to_s.strip
        return unprocessable('Informe o novo nome do anexo.') if novo.blank?

        attachment.title = novo
        return unprocessable(attachment.errors.full_messages.to_sentence) unless attachment.save

        ok(attachment)
      end

      # **Só o autor exclui, checado NO SERVIDOR** (BE-229). Registro sem arquivo
      # (o anexo cujo binário se perdeu) é removido normalmente — no legado ele
      # travava a tela em vez de sair.
      def destroy!(attachment:, actor:)
        unless attachment.deletable_by?(actor)
          return forbidden('Somente quem enviou o anexo pode removê-lo.')
        end

        renegotiation = attachment.renegotiation
        attachment.destroy!
        renegotiation.reload

        ok({ deleted: true, id: attachment.id.to_s,
             attachments_count: renegotiation.attachments_count })
      end

      # Reconcilia o contador (DB-195). Usado pela carga e pelo fixup; a operação
      # normal mantém o contador pelo `counter_cache`.
      def reset_counter!(renegotiation)
        Renegotiation.reset_counters(renegotiation.id, :attachments)
        renegotiation.reload.attachments_count
      end

      private

      # Grape entrega `{filename:, type:, tempfile:}`; Rack entrega
      # `ActionDispatch::Http::UploadedFile`. As duas formas chegam aqui — é a
      # mesma normalização que `Sfg::Attachments#to_attachable` faz, e ela mora
      # aqui porque lá é privada.
      def payload_for(arquivo)
        return arquivo unless arquivo.is_a?(Hash)

        { io: arquivo[:tempfile], filename: arquivo[:filename], content_type: arquivo[:type] }
      end
    end
  end
end
