//
//  ChatView.swift
//  MediumFunctionCalls
//
//  Created by kemo konteh on 11/7/23.
//

import SwiftUI
import Combine

struct ChatMessage {
    let id: String
    let content: String
    let createdAt: Date
    let sender: MessageSender
}

enum MessageSender {
    case user
    case chatGPT
}

class ChatViewModel: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    @Published var chatMessages: [ChatMessage] = []

    @Published var lastMessageID: String = ""

    let openAIService: OpenAIService

    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }

    func sendMessage (message: String) {
        guard message != "" else {return}

        let myMessage = ChatMessage(id: UUID().uuidString, content: message, createdAt: Date(), sender: .user)
        chatMessages.append(myMessage)
        lastMessageID = myMessage.id

        openAIService.makeRequest(message: OpenAIMessage(role: "user", content: message))
            .sink { completion in
                /// - Handle Error here
                switch completion {
                case .failure(let error): print(error.localizedDescription)
                case .finished: break
                }
            } receiveValue: { response in
                self.handleResponse(response: response)
            }
            .store(in: &cancellables)
    }

    func handleResponse(response: OpenAIResponse) {
        guard let message = response.choices.first?.message else { return }
        print("message", message)
        if let functionCall = message.function_call {
            handleFunctionCall(functionCall: functionCall)
            chatMessages.append(ChatMessage(id: response.id, content: "Calling Function \(functionCall.name)", createdAt: Date(), sender: .chatGPT))
        } else if let textResponse = message.content?.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) {
            chatMessages.append(ChatMessage(id: response.id, content: textResponse, createdAt: Date(), sender: .chatGPT))
            lastMessageID = response.id
        }
    }

    func handleFunctionCall(functionCall: FunctionCall) {
        self.openAIService.handleFunctionCall(functionCall: functionCall) { result in
            switch result {
            case .success(let functionResponse):
                self.openAIService.makeRequest(
                    message: OpenAIMessage(
                        role: "function",
                        content: functionResponse,
                        name: functionCall.name
                    )
                )
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error): print("error", error)
                    case .finished: break
                    }
                }, receiveValue: { response in
                    guard let responseMessage = response.choices.first?.message else {
                        return
                    }
                    guard let textResponse = responseMessage.content?
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\""))) else {return}

                    let chatGPTMessage = ChatMessage(id: response.id,
                                                     content: textResponse,
                                                     createdAt: Date(),
                                                     sender: .chatGPT
                    )

                    self.chatMessages.append(chatGPTMessage)
                    self.lastMessageID = chatGPTMessage.id
                    print("final",response)
                })
                .store(in: &self.cancellables)

            case .failure(let error):
                print(error.localizedDescription)
            }
        }
    }
}

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel = ChatViewModel()
    @State var message: String = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text("SwiftUI ChatGPT Function Calls")
                        .font(.title)
                        .fontWeight(.bold)
                    Spacer()
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack {
                            ForEach(viewModel.chatMessages, id: \.id) { message in
                                MessageView(message: message)
                            }
                        }
                    }
                    .onChange(of: viewModel.lastMessageID) { id in
                        withAnimation{
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }

                HStack {
                    TextField("Enter a message", text: $message) {}
                        .padding()
                        .background(colorScheme == .dark ? .gray.opacity(0.2) : .gray.opacity(0.4))
                        .cornerRadius(12)
                    Button{
                        viewModel.sendMessage(message: message)
                        message = ""
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding()
        }
    }
}

struct MessageView: View {
    var message: ChatMessage
    var body: some View {
            HStack{
                if message.sender == .user{Spacer()}
                Text(message.content)
                    .foregroundColor(message.sender == .user ? .white : nil)
                    .padding()
                    .background(message.sender == .user ? .blue : .gray.opacity(0.4))
                    .cornerRadius(24)
                if message.sender == .chatGPT{Spacer()}
            }
        }
}

#Preview {
    ChatView()
}
