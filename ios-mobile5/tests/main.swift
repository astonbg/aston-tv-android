import Foundation

let cases: [(Any?, Bool)] = [(true,true),(false,false),(1,true),(0,false),("1",true),("true",true),("false",false),("0",false),(nil,false),(2,false)]
for (input, expected) in cases {
    precondition(GatewayContract.isEnabled(input) == expected, "Gateway boolean compatibility failed")
}
print("Gateway boolean contract: 10 cases passed")
