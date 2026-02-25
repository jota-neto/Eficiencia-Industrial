/*
==============================================================================
PROJETO: Eficiência Industrial - O custo Invisível do Desequilíbrio
AUTOR: João Neto
DESCRIÇÃO: Pipeline de ETL para cálculo de OEE e Impacto Financeiro.
==============================================================================
*/

let
    // ==========================================
    // 1. IMPORTAÇÃO E CONFIGURAÇÃO DE DIRETÓRIO
    // ==========================================
   
    Fonte = Csv.Document(
         File.Contents("C:\Users\jnett\Documents\estudosDeCaso\02_producao\dados		\Base_Analitica_Producao.csv"),
        [Delimiter=",", Columns=24, Encoding=65001, QuoteStyle=QuoteStyle.None]
    ),

    #"Cabeçalhos Promovidos" = Table.PromoteHeaders(Fonte, [PromoteAllScalars=true]),

    // ==========================================
    // 2. TIPAGEM E PADRONIZAÇÃO
    // ==========================================
    #"Tipo Alterado" = Table.TransformColumnTypes(#"Cabeçalhos Promovidos",{
        {"id_registro", Int64.Type}, {"data_inicio", type date}, {"data_fim", type date},
        {"hora_inicio", type time}, {"hora_fim", type time}, {"turno", type text},
        {"quantidade_planejada_hora", Int64.Type}, {"tempo_ciclo_teorico_segundos", Int64.Type},
        {"tempo_producao_planejado_minutos", Int64.Type}, {"tempo_parada_minutos", Int64.Type},
        {"quantidade_produzida_total", Int64.Type}, {"quantidade_boa", Int64.Type},
        {"quantidade_refugada", Int64.Type}, {"custo_unitario", type text}, {"prejuizo_financeiro", type text}
    }),

    // Limpeza de texto: Remove "Nenhuma" para permitir análises de texto limpas
    #"Limpeza Motivo Parada" = Table.ReplaceValue(#"Tipo Alterado","Nenhuma","",Replacer.ReplaceText,{"motivo_parada"}),

    // ==========================================
    // 3. CÁLCULO DOS COMPONENTES OEE
    // ==========================================
    
    // Disponibilidade: Tempo Real / Tempo Planejado
    #"Cálculo Disponibilidade" = Table.AddColumn(#"Limpeza Motivo Parada", "disponibilidade", 
        each ([tempo_producao_planejado_minutos] - [tempo_parada_minutos]) / [tempo_producao_planejado_minutos], Percentage.Type),

    // Performance: Produção Real vs Capacidade Teórica
    #"Cálculo Performance" = Table.AddColumn(#"Cálculo Disponibilidade", "performance", 
        each if ([tempo_producao_planejado_minutos] - [tempo_parada_minutos]) = 0 then 0 
        else ([quantidade_produzida_total] * ([tempo_ciclo_teorico_segundos] / 60)) / ([tempo_producao_planejado_minutos] - [tempo_parada_minutos]), Percentage.Type),

    // Qualidade: Peças Boas vs Produção Total
    #"Cálculo Qualidade" = Table.AddColumn(#"Cálculo Performance", "qualidade", 
        each if [quantidade_produzida_total] = 0 then 0 else [quantidade_boa] / [quantidade_produzida_total], Percentage.Type),

    // OEE Final: O produto das três dimensões
    #"Cálculo OEE" = Table.AddColumn(#"Cálculo Qualidade", "oee", each [disponibilidade] * [performance] * [qualidade], Percentage.Type),

    // ==========================================
    // 4. MODELAGEM FINANCEIRA (IMPACTO REAL)
    // ==========================================
    
    // Ajuste de Localidade e Escala Monetária (Divisão por 100 para centavos)
    #"Ajuste Localidade" = Table.TransformColumnTypes(#"Cálculo OEE", {{"custo_unitario", type number}, {"prejuizo_financeiro", type number}}, "en-US"),
    #"Custo Real" = Table.AddColumn(#"Ajuste Localidade", "custo_unit_ajustado", each [custo_unitario] / 100, Currency.Type),
    #"Prejuizo Refugo Real" = Table.AddColumn(#"Custo Real", "prejuizo_refugo", each [prejuizo_financeiro] / 100, Currency.Type),

    // Perda por Parada: (Tempo Parada em Horas) * Capacidade * Custo
    #"Perda Parada" = Table.AddColumn(#"Prejuizo Refugo Real", "perda_por_parada", 
        each ([tempo_parada_minutos] / 60) * [quantidade_planejada_hora] * [custo_unit_ajustado], Currency.Type),

    // Perda Total: Soma das perdas de Disponibilidade e Qualidade
    #"Perda Total" = Table.AddColumn(#"Perda Parada", "perda_total", each [prejuizo_refugo] + [perda_por_parada], Currency.Type)

in
    #"Perda Total"