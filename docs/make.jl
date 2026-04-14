using Documenter
using OndaVision

makedocs(;
         repo=Remotes.GitHub("palday", "OndaVision.jl"),
         sitename="OndaVision",
         doctest=true,
         checkdocs=:exports,
         warnonly=[:cross_references],
         format=Documenter.HTML(; edit_link="main"),
         pages=["index.md",
                "api.md"])

deploydocs(; repo="github.com/palday/OndaVision.jl.git",
           devbranch="main",
           push_preview=true)
