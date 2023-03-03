import UIKit
import NGLogging
import NGTheme

public protocol SpecialOfferBuilder {
    func build(onCloseRequest: (() -> ())?) -> UIViewController
    func build(offerId: String, onCloseRequest: (() -> ())?) -> UIViewController
}

public class SpecialOfferBuilderImpl: SpecialOfferBuilder {
    
    //  MARK: - Dependencies
    
    private let specialOfferService: SpecialOfferService
    private let ngTheme: NGThemeColors
    
    //  MARK: - Lifecycle
    
    public init(specialOfferService: SpecialOfferService, ngTheme: NGThemeColors) {
        self.specialOfferService = specialOfferService
        self.ngTheme = ngTheme
    }
    
    //  MARK: - Public Functions

    public func build(onCloseRequest: (() -> ())?) -> UIViewController {
        internalBuild(offerId: nil, onCloseRequest: onCloseRequest)
    }
    
    public func build(offerId: String, onCloseRequest: (() -> ())?) -> UIViewController {
        internalBuild(offerId: offerId, onCloseRequest: onCloseRequest)
    }
    
    //  MARK: - Private Functions

    private func internalBuild(offerId: String?, onCloseRequest: (() -> ())?) -> UIViewController {
        let controller = SpecialOfferViewController(ngTheme: ngTheme)

        let router = SpecialOfferRouter()
        router.parentViewController = controller

        let presenter = SpecialOfferPresenter()
        presenter.output = controller

        let interactor = SpecialOfferInteractor(
            offerId: offerId,
            specialOfferService: specialOfferService,
            setSpecialOfferSeenUseCase: SetSpecialOfferSeenUseCaseImpl(
                specialOfferService: specialOfferService,
                specialOfferScheduleService: SpecialOfferScheduleServiceImpl()
            ),
            eventsLogger: LoggersFactory().createDefaultEventsLogger(),
            onCloseRequest: onCloseRequest
        )
        interactor.output = presenter
        interactor.router = router

        controller.output = interactor

        return controller
    }
}
