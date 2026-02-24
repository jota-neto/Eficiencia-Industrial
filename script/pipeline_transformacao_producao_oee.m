let
    // ============================
    // 1. IMPORTAÇÃO DO ARQUIVO CSV
    // ============================
    Fonte = Csv.Document(
        File.Contents("C:\Users\jnett\Documents\estudosDeCaso\02_producao\dados\Base_Analitica_Producao.csv"),
        [Delimiter=",", Columns=24, Encoding=65001, QuoteStyle=QuoteStyle.None]
    ),

    // Promove a primeira linha como cabeçalho da tabela
    #"Cabeçalhos Promovidos" = Table.PromoteHeaders(Fonte, [PromoteAllScalars=true]),

    // ============================
    // 2. DEFINIÇÃO DOS TIPOS DE DADOS
    // ============================
    #"Tipo Alterado" = Table.TransformColumnTypes(#"Cabeçalhos Promovidos",{
        {"id_registro", Int64.Type},
        {"data_inicio", type date},
        {"data_fim", type date},
        {"hora_inicio", type time},
        {"hora_fim", type time},
        {"turno", type text},
        {"id_ordem_producao", type text},
        {"local_de_envio", type text},
        {"id_produto", type text},
        {"nome_produto", type text},
        {"id_maquina", type text},
        {"id_linha_producao", type text},
        {"quantidade_planejada_hora", Int64.Type},
        {"tempo_ciclo_teorico_segundos", Int64.Type},
        {"tempo_producao_planejado_minutos", Int64.Type},
        {"tempo_parada_minutos", Int64.Type},
        {"motivo_parada", type text},
        {"quantidade_produzida_total", Int64.Type},
        {"quantidade_boa", Int64.Type},
        {"quantidade_refugada", Int64.Type},
        {"id_operador", type text},
        {"nome_operador", type text},
        {"custo_unitario", Int64.Type},
        {"prejuizo_financeiro", Int64.Type}
    }),

    // ============================
    // 3. VALIDAÇÃO DE DADOS
    // ============================
    // Verifica se quantidade boa + refugada = total produzido
    #"Criação Coluna Verificação Qtde Produzida" =
        Table.AddColumn(#"Tipo Alterado", "verificacao_qtde_produzida",
        each if [quantidade_boa] + [quantidade_refugada] = [quantidade_produzida_total]
        then 1 else 0),

    // ============================
    // 4. CÁLCULOS OPERACIONAIS
    // ============================
    // Calcula o tempo real em operação
    #"Cálculo Tempo em Operação" =
        Table.AddColumn(#"Criação Coluna Verificação Qtde Produzida",
        "tempo_em_operacao",
        each [tempo_producao_planejado_minutos] - [tempo_parada_minutos]),

    // Remove texto "Nenhuma" da coluna motivo_parada
    #"Valor Substituído ""Nenhuma"" por Vazio" =
        Table.ReplaceValue(#"Cálculo Tempo em Operação",
        "Nenhuma","",
        Replacer.ReplaceText,{"motivo_parada"}),

    // ============================
    // 5. CÁLCULO DO OEE
    // ============================

    // Disponibilidade = Tempo Operação / Tempo Planejado
    #"Cálculo Disponibilidade" =
        Table.AddColumn(#"Valor Substituído ""Nenhuma"" por Vazio",
        "disponibilidade",
        each ([tempo_producao_planejado_minutos] - [tempo_parada_minutos])
        / [tempo_producao_planejado_minutos]),

    #"Coluna Disponibilidade Alterado para Percentual" =
        Table.TransformColumnTypes(#"Cálculo Disponibilidade",
        {{"disponibilidade", Percentage.Type}}),

    // Performance = Produção Real x Tempo Ciclo / Tempo Operação
    #"Cálculo Performance" =
        Table.AddColumn(#"Coluna Disponibilidade Alterado para Percentual",
        "Personalizar",
        each if ([tempo_producao_planejado_minutos] - [tempo_parada_minutos]) = 0
        then 0
        else ([quantidade_produzida_total] *
              ([tempo_ciclo_teorico_segundos] / 60))
              / ([tempo_producao_planejado_minutos] - [tempo_parada_minutos])),

    #"Coluna Performance Alterado para Percentual" =
        Table.TransformColumnTypes(#"Cálculo Performance",
        {{"Personalizar", Percentage.Type}}),

    // Qualidade = Quantidade Boa / Quantidade Total
    #"Cálculo Qualidade" =
        Table.AddColumn(#"Coluna Performance Alterado para Percentual",
        "qualidade",
        each if [quantidade_produzida_total] = 0
        then 0
        else [quantidade_boa] / [quantidade_produzida_total]),

    #"Coluna Qualidade Alterado para Percentual" =
        Table.TransformColumnTypes(#"Cálculo Qualidade",
        {{"qualidade", Percentage.Type}}),

    // Renomeia coluna Performance
    #"Colunas Renomeadas" =
        Table.RenameColumns(#"Coluna Qualidade Alterado para Percentual",
        {{"Personalizar", "performance"}}),

    // OEE = Disponibilidade x Performance x Qualidade
    #"Cálculo OEE" =
        Table.AddColumn(#"Colunas Renomeadas",
        "oee",
        each [disponibilidade] * [performance] * [qualidade]),

    #"Coluna OEE Alterado Para Percentual" =
        Table.TransformColumnTypes(#"Cálculo OEE",
        {{"oee", Percentage.Type},
         {"custo_unitario", type text},
         {"prejuizo_financeiro", type text}}),

    // ============================
    // 6. AJUSTE MONETÁRIO
    // ============================
    // Converte para número com localidade americana
    #"Tipo Alterado com Localidade" =
        Table.TransformColumnTypes(#"Coluna OEE Alterado Para Percentual",
        {{"custo_unitario", type number},
         {"prejuizo_financeiro", type number}},
        "en-US"),

    // Divide por 100 para ajustar centavos
    #"Alteração Custo Unitario" =
        Table.AddColumn(#"Tipo Alterado com Localidade",
        "custo_unitario1",
        each [custo_unitario] / 100),

    #"Ajuste Prejuizo Financeiro" =
        Table.AddColumn(#"Alteração Custo Unitario",
        "prejuizo_financeiro1",
        each [prejuizo_financeiro] / 100),

    // ============================
    // 7. CÁLCULOS FINANCEIROS
    // ============================

    // Perda por parada
    #"Cálculo de Perda por Parada" =
        Table.AddColumn(#"Ajuste Prejuizo Financeiro",
        "perda_por_parada",
        each ([tempo_parada_minutos] / 60)
        * [quantidade_planejada_hora]
        * [custo_unitario1]),

    #"Alteração Tipo de Dado" =
        Table.TransformColumnTypes(#"Cálculo de Perda por Parada",
        {{"perda_por_parada", Currency.Type}}),

    // Valor realizado (produção boa)
    #"Cálculo do Valor Realizado" =
        Table.AddColumn(#"Alteração Tipo de Dado",
        "valor_realizado",
        each [quantidade_boa] * [custo_unitario1]),

    #"Alteração Tipo de Dado R$" =
        Table.TransformColumnTypes(#"Cálculo do Valor Realizado",
        {{"valor_realizado", Currency.Type}}),

    // Perda total = Refugo + Paradas
    #"Cálculo de Prejuizo Total" =
        Table.AddColumn(#"Alteração Tipo de Dado R$",
        "perda_total",
        each [prejuizo_financeiro1] + [perda_por_parada]),

    #"Alteração Tipo de Dado $" =
        Table.TransformColumnTypes(#"Cálculo de Prejuizo Total",
        {{"perda_total", Currency.Type}}),

    // Renomeia prejuízo financeiro para prejuízo refugo
    #"Alteração para prejuizo_refugo" =
        Table.RenameColumns(#"Alteração Tipo de Dado $",
        {{"prejuizo_financeiro1", "prejuizo_refugo"}})

in
    #"Alteração para prejuizo_refugo"