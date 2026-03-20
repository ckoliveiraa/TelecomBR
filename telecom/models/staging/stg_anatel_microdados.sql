with source as (
    select * from {{ source('anatel', 'microdados') }}
),

renamed as (
    select distinct
        -- tempo
        ano,
        mes,

        -- localização
        sigla_uf,
        id_municipio,

        -- empresa
        cnpj,
        empresa,
        porte_empresa,

        -- produto
        tecnologia,
        transmissao,
        velocidade,
        produto,

        -- métricas
        acessos

    from source
)

select * from renamed
where acessos is not null